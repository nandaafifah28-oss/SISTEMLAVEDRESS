-- Make purchase, rental, cancellation, return, movement, and inventory variant-aware.
-- Run after 24_dress_variant_schema_backfill.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.ensure_dress_variant(
  p_dress_id bigint,
  p_size varchar
)
RETURNS SETOF public.dress_variants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  variant_row public.dress_variants%ROWTYPE;
BEGIN
  IF current_app_role() NOT IN ('admin','staff','accounting') THEN
    RAISE EXCEPTION 'Role Anda tidak memiliki akses mengelola varian dress';
  END IF;

  IF p_dress_id IS NULL OR nullif(upper(trim(p_size)), '') IS NULL THEN
    RAISE EXCEPTION 'Master dress dan ukuran wajib dipilih';
  END IF;

  PERFORM 1
  FROM public.dresses
  WHERE id = p_dress_id
    AND is_active
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Master dress tidak ditemukan atau sudah nonaktif';
  END IF;

  INSERT INTO public.dress_variants(
    dress_id,
    size,
    condition,
    status
  )
  SELECT
    p_dress_id,
    upper(trim(p_size)),
    'Good',
    'Not Available'
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.dress_variants existing
    WHERE existing.dress_id = p_dress_id
      AND existing.normalized_size = upper(trim(p_size))
  );

  SELECT *
  INTO variant_row
  FROM public.dress_variants
  WHERE dress_id = p_dress_id
    AND normalized_size = upper(trim(p_size))
  FOR UPDATE;

  RETURN NEXT variant_row;
END;
$$;

REVOKE ALL
ON FUNCTION public.ensure_dress_variant(bigint,varchar)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.ensure_dress_variant(bigint,varchar)
TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_purchase_detail_variant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  variant_dress_id bigint;
BEGIN
  IF NEW.quantity IS NULL OR NEW.quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity pembelian harus lebih besar dari nol';
  END IF;

  IF NEW.dress_variant_id IS NULL THEN
    RAISE EXCEPTION 'Varian ukuran wajib dipilih untuk detail pembelian';
  END IF;

  SELECT dress_id
  INTO variant_dress_id
  FROM public.dress_variants
  WHERE id = NEW.dress_variant_id;

  IF variant_dress_id IS NULL
    OR variant_dress_id IS DISTINCT FROM NEW.dress_id
  THEN
    RAISE EXCEPTION 'Varian tidak sesuai dengan master dress';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS validate_purchase_detail_variant
ON public.purchase_details;

CREATE TRIGGER validate_purchase_detail_variant
BEFORE INSERT OR UPDATE OF dress_id, dress_variant_id, quantity
ON public.purchase_details
FOR EACH ROW
EXECUTE FUNCTION public.validate_purchase_detail_variant();

CREATE OR REPLACE FUNCTION public.record_purchase_inventory_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  purchase_code_value varchar;
  previous_status varchar;
  next_status varchar;
BEGIN
  SELECT purchase_code
  INTO purchase_code_value
  FROM public.purchases
  WHERE id = NEW.purchase_id;

  IF purchase_code_value IS NULL THEN
    RAISE EXCEPTION 'Purchase tidak ditemukan';
  END IF;

  SELECT status
  INTO previous_status
  FROM public.dress_variants
  WHERE id = NEW.dress_variant_id
  FOR UPDATE;

  IF previous_status IS NULL THEN
    RAISE EXCEPTION 'Varian dress tidak ditemukan';
  END IF;

  UPDATE public.dress_variants
  SET quantity = quantity + NEW.quantity,
      available_quantity = available_quantity + NEW.quantity,
      condition = CASE
        WHEN quantity = 0 THEN 'Good'
        WHEN condition = 'Good' THEN 'Good'
        ELSE 'Mixed'
      END,
      status = 'Available',
      updated_at = now()
  WHERE id = NEW.dress_variant_id
  RETURNING status INTO next_status;

  INSERT INTO public.dress_movements(
    dress_id,
    dress_variant_id,
    movement_type,
    reference_id,
    reference_code,
    status_before,
    status_after,
    quantity_delta,
    available_delta,
    rented_delta,
    unavailable_delta,
    description
  )
  VALUES (
    NEW.dress_id,
    NEW.dress_variant_id,
    'PURCHASE_IN',
    NEW.purchase_id,
    purchase_code_value,
    previous_status,
    next_status,
    NEW.quantity,
    NEW.quantity,
    0,
    0,
    'Stok ukuran masuk melalui pembelian'
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_purchase_detail_inventory
ON public.purchase_details;

CREATE TRIGGER after_purchase_detail_inventory
AFTER INSERT
ON public.purchase_details
FOR EACH ROW
EXECUTE FUNCTION public.record_purchase_inventory_movement();

CREATE OR REPLACE FUNCTION public.create_purchase_transaction(
  p_supplier_id bigint,
  p_purchase_date date,
  p_payment_status varchar,
  p_payment_method varchar,
  p_dress_id bigint DEFAULT NULL,
  p_dress_name varchar DEFAULT NULL,
  p_category_id bigint DEFAULT NULL,
  p_size varchar DEFAULT NULL,
  p_color varchar DEFAULT NULL,
  p_purchase_price numeric DEFAULT 0,
  p_rental_price numeric DEFAULT 0,
  p_quantity integer DEFAULT 1
)
RETURNS TABLE(
  purchase_id bigint,
  purchase_code varchar,
  dress_id bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  purchase_row public.purchases%ROWTYPE;
  selected_dress_id bigint := p_dress_id;
  variant_row public.dress_variants%ROWTYPE;
  total_value numeric;
BEGIN
  IF current_app_role() NOT IN ('admin','staff','accounting') THEN
    RAISE EXCEPTION 'Role Anda tidak memiliki akses membuat pembelian';
  END IF;

  IF p_supplier_id IS NULL OR p_purchase_date IS NULL THEN
    RAISE EXCEPTION 'Supplier dan tanggal pembelian wajib diisi';
  END IF;

  IF p_payment_status NOT IN ('Paid','Unpaid')
    OR p_payment_method NOT IN ('Cash','Transfer','E-Wallet')
  THEN
    RAISE EXCEPTION 'Status atau metode pembayaran pembelian tidak valid';
  END IF;

  IF p_purchase_price IS NULL
    OR p_purchase_price <= 0
    OR p_quantity IS NULL
    OR p_quantity <= 0
  THEN
    RAISE EXCEPTION 'Harga beli dan quantity harus lebih besar dari nol';
  END IF;

  IF nullif(upper(trim(p_size)), '') IS NULL THEN
    RAISE EXCEPTION 'Ukuran dress wajib dipilih';
  END IF;

  IF coalesce(p_rental_price, 0) < 0 THEN
    RAISE EXCEPTION 'Harga sewa tidak boleh negatif';
  END IF;

  IF selected_dress_id IS NULL THEN
    IF nullif(trim(p_dress_name), '') IS NULL OR p_category_id IS NULL THEN
      RAISE EXCEPTION 'Nama dan kategori model dress baru wajib diisi';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.dresses
      WHERE is_active
        AND lower(btrim(name)) = lower(btrim(p_dress_name))
        AND category_id = p_category_id
        AND lower(btrim(coalesce(color, ''))) = lower(btrim(coalesce(p_color, '')))
    ) THEN
      RAISE EXCEPTION 'Model dengan nama, kategori, dan warna tersebut sudah terdaftar; pilih model yang ada dan tambahkan ukuran';
    END IF;

    INSERT INTO public.dresses(
      name,
      category_id,
      color,
      purchase_price,
      rental_price,
      supplier_id,
      condition,
      status,
      is_active
    )
    VALUES (
      trim(p_dress_name),
      p_category_id,
      nullif(trim(p_color), ''),
      p_purchase_price,
      coalesce(p_rental_price, 0),
      p_supplier_id,
      'Good',
      'Available',
      true
    )
    RETURNING id INTO selected_dress_id;
  ELSE
    PERFORM 1
    FROM public.dresses
    WHERE id = selected_dress_id
      AND is_active
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Master dress tidak ditemukan atau sudah nonaktif';
    END IF;
  END IF;

  INSERT INTO public.dress_variants(
    dress_id,
    size,
    condition,
    status
  )
  SELECT
    selected_dress_id,
    upper(trim(p_size)),
    'Good',
    'Not Available'
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.dress_variants existing
    WHERE existing.dress_id = selected_dress_id
      AND existing.normalized_size = upper(trim(p_size))
  );

  SELECT *
  INTO variant_row
  FROM public.dress_variants
  WHERE dress_id = selected_dress_id
    AND normalized_size = upper(trim(p_size))
  FOR UPDATE;

  total_value := p_purchase_price * p_quantity;

  INSERT INTO public.purchases(
    supplier_id,
    purchase_date,
    total_amount,
    payment_status,
    payment_method
  )
  VALUES (
    p_supplier_id,
    p_purchase_date,
    total_value,
    p_payment_status,
    p_payment_method
  )
  RETURNING * INTO purchase_row;

  INSERT INTO public.purchase_details(
    purchase_id,
    dress_id,
    dress_variant_id,
    quantity,
    purchase_price,
    subtotal
  )
  VALUES (
    purchase_row.id,
    selected_dress_id,
    variant_row.id,
    p_quantity,
    p_purchase_price,
    total_value
  );

  RETURN QUERY
  SELECT
    purchase_row.id,
    purchase_row.purchase_code,
    selected_dress_id;
END;
$$;

REVOKE ALL
ON FUNCTION public.create_purchase_transaction(
  bigint,
  date,
  varchar,
  varchar,
  bigint,
  varchar,
  bigint,
  varchar,
  varchar,
  numeric,
  numeric,
  integer
)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.create_purchase_transaction(
  bigint,
  date,
  varchar,
  varchar,
  bigint,
  varchar,
  bigint,
  varchar,
  varchar,
  numeric,
  numeric,
  integer
)
TO authenticated;

CREATE OR REPLACE FUNCTION public.create_rental_variant_transaction(
  p_customer_id bigint,
  p_dress_id bigint,
  p_dress_variant_id bigint,
  p_rental_date date,
  p_return_due_date date,
  p_total_rental numeric,
  p_rental_code varchar DEFAULT NULL,
  p_deposit_amount numeric DEFAULT 0,
  p_rental_status varchar DEFAULT 'Booked',
  p_payment_amount numeric DEFAULT 0,
  p_payment_date date DEFAULT current_date,
  p_payment_method varchar DEFAULT 'Cash',
  p_payment_type varchar DEFAULT 'DP'
)
RETURNS TABLE(
  rental_id bigint,
  rental_code varchar,
  payment_code varchar
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_rental public.rentals%ROWTYPE;
  variant_row public.dress_variants%ROWTYPE;
  new_payment_code varchar;
BEGIN
  IF current_app_role() NOT IN ('admin','staff','accounting') THEN
    RAISE EXCEPTION 'Role Anda tidak memiliki akses membuat rental';
  END IF;

  IF p_customer_id IS NULL
    OR p_dress_id IS NULL
    OR p_dress_variant_id IS NULL
  THEN
    RAISE EXCEPTION 'Customer, dress, dan ukuran wajib dipilih';
  END IF;

  IF p_rental_date IS NULL
    OR p_return_due_date IS NULL
    OR p_return_due_date < p_rental_date
  THEN
    RAISE EXCEPTION 'Tanggal rental tidak valid';
  END IF;

  IF coalesce(p_total_rental, 0) < 0
    OR coalesce(p_deposit_amount, 0) < 0
    OR coalesce(p_payment_amount, 0) < 0
  THEN
    RAISE EXCEPTION 'Nominal tidak boleh negatif';
  END IF;

  IF p_payment_amount > p_total_rental THEN
    RAISE EXCEPTION 'Pembayaran melebihi total rental';
  END IF;

  IF p_rental_status NOT IN ('Booked','Ongoing') THEN
    RAISE EXCEPTION 'Status rental tidak valid';
  END IF;

  SELECT variant.*
  INTO variant_row
  FROM public.dress_variants variant
  JOIN public.dresses model
    ON model.id = variant.dress_id
  WHERE variant.id = p_dress_variant_id
    AND variant.dress_id = p_dress_id
    AND model.is_active
  FOR UPDATE OF variant;

  IF variant_row.id IS NULL THEN
    RAISE EXCEPTION 'Varian dress tidak ditemukan atau master nonaktif';
  END IF;

  IF variant_row.available_quantity <= 0 THEN
    RAISE EXCEPTION 'Ukuran tersebut tidak memiliki stok tersedia';
  END IF;

  INSERT INTO public.rentals(
    rental_code,
    customer_id,
    rental_date,
    return_due_date,
    total_amount,
    total_rental,
    deposit_amount,
    status,
    rental_status,
    payment_status
  )
  VALUES (
    coalesce(p_rental_code, next_business_code('rental')),
    p_customer_id,
    p_rental_date,
    p_return_due_date,
    p_total_rental,
    p_total_rental,
    p_deposit_amount,
    p_rental_status,
    p_rental_status,
    CASE
      WHEN p_payment_amount <= 0 THEN 'Unpaid'
      WHEN p_payment_amount < p_total_rental THEN 'Partially Paid'
      ELSE 'Paid'
    END
  )
  RETURNING * INTO new_rental;

  INSERT INTO public.rental_details(
    rental_id,
    dress_id,
    dress_variant_id,
    rental_price,
    quantity,
    subtotal
  )
  VALUES (
    new_rental.id,
    p_dress_id,
    p_dress_variant_id,
    p_total_rental,
    1,
    p_total_rental
  );

  UPDATE public.dress_variants
  SET available_quantity = available_quantity - 1,
      rented_quantity = rented_quantity + 1,
      status = CASE
        WHEN available_quantity - 1 > 0 THEN 'Available'
        ELSE 'Rented'
      END,
      updated_at = now()
  WHERE id = p_dress_variant_id;

  INSERT INTO public.dress_movements(
    dress_id,
    dress_variant_id,
    movement_type,
    reference_id,
    reference_code,
    status_before,
    status_after,
    quantity_delta,
    available_delta,
    rented_delta,
    unavailable_delta,
    description
  )
  VALUES (
    p_dress_id,
    p_dress_variant_id,
    'RENTAL_OUT',
    new_rental.id,
    new_rental.rental_code,
    variant_row.status,
    CASE
      WHEN variant_row.available_quantity - 1 > 0 THEN 'Available'
      ELSE 'Rented'
    END,
    0,
    -1,
    1,
    0,
    'Satu unit ukuran disewa'
  );

  IF p_payment_amount > 0 THEN
    new_payment_code := next_business_code('payment');

    INSERT INTO public.payments(
      payment_code,
      rental_id,
      payment_date,
      amount,
      payment_method,
      payment_type,
      notes,
      description
    )
    VALUES (
      new_payment_code,
      new_rental.id,
      p_payment_date,
      p_payment_amount,
      p_payment_method,
      p_payment_type,
      'Pembayaran awal saat transaksi rental',
      'Pembayaran awal rental'
    );
  END IF;

  RETURN QUERY
  SELECT
    new_rental.id,
    new_rental.rental_code,
    new_payment_code;
END;
$$;

REVOKE ALL
ON FUNCTION public.create_rental_variant_transaction(
  bigint,
  bigint,
  bigint,
  date,
  date,
  numeric,
  varchar,
  numeric,
  varchar,
  numeric,
  date,
  varchar,
  varchar
)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.create_rental_variant_transaction(
  bigint,
  bigint,
  bigint,
  date,
  date,
  numeric,
  varchar,
  numeric,
  varchar,
  numeric,
  date,
  varchar,
  varchar
)
TO authenticated;

-- Keep old clients from silently creating size-less rentals after migration.

CREATE OR REPLACE FUNCTION public.create_rental_transaction(
  p_customer_id bigint,
  p_dress_id bigint,
  p_rental_date date,
  p_return_due_date date,
  p_total_rental numeric,
  p_rental_code varchar DEFAULT NULL,
  p_deposit_amount numeric DEFAULT 0,
  p_rental_status varchar DEFAULT 'Booked',
  p_payment_amount numeric DEFAULT 0,
  p_payment_date date DEFAULT current_date,
  p_payment_method varchar DEFAULT 'Cash',
  p_payment_type varchar DEFAULT 'DP'
)
RETURNS TABLE(
  rental_id bigint,
  rental_code varchar,
  payment_code varchar
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'Pilih ukuran dress; gunakan create_rental_variant_transaction';
END;
$$;

REVOKE ALL
ON FUNCTION public.create_rental_transaction(
  bigint,
  bigint,
  date,
  date,
  numeric,
  varchar,
  numeric,
  varchar,
  numeric,
  date,
  varchar,
  varchar
)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.create_rental_transaction(
  bigint,
  bigint,
  date,
  date,
  numeric,
  varchar,
  numeric,
  varchar,
  numeric,
  date,
  varchar,
  varchar
)
TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_rental(
  p_rental_id bigint,
  p_reason text,
  p_deposit_action varchar,
  p_cancelled_at timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rental_row public.rentals%ROWTYPE;
  paid_amount numeric;
  detail_row record;
  next_status varchar;
BEGIN
  IF current_app_role() NOT IN ('admin','staff','accounting') THEN
    RAISE EXCEPTION 'Role tidak diizinkan membatalkan rental';
  END IF;

  SELECT *
  INTO rental_row
  FROM public.rentals
  WHERE id = p_rental_id
  FOR UPDATE;

  IF rental_row.id IS NULL THEN
    RAISE EXCEPTION 'Rental tidak ditemukan';
  END IF;

  IF coalesce(rental_row.rental_status, rental_row.status) IN ('Cancelled','Completed','Returned') THEN
    RAISE EXCEPTION 'Rental sudah tidak dapat dibatalkan';
  END IF;

  IF nullif(trim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi';
  END IF;

  IF p_deposit_action NOT IN ('REFUND','FORFEIT') THEN
    RAISE EXCEPTION 'Penanganan deposit tidak valid';
  END IF;

  FOR detail_row IN
    SELECT
      detail.dress_id,
      detail.dress_variant_id,
      detail.quantity,
      variant.status AS previous_status,
      variant.rented_quantity
    FROM public.rental_details detail
    JOIN public.dress_variants variant
      ON variant.id = detail.dress_variant_id
    WHERE detail.rental_id = p_rental_id
    FOR UPDATE OF variant
  LOOP
    IF detail_row.rented_quantity < detail_row.quantity THEN
      RAISE EXCEPTION 'Jumlah unit disewa tidak konsisten untuk varian %',
        detail_row.dress_variant_id;
    END IF;

    UPDATE public.dress_variants
    SET rented_quantity = rented_quantity - detail_row.quantity,
        available_quantity = available_quantity + detail_row.quantity,
        status = 'Available',
        updated_at = now()
    WHERE id = detail_row.dress_variant_id
    RETURNING status INTO next_status;

    INSERT INTO public.dress_movements(
      dress_id,
      dress_variant_id,
      movement_type,
      reference_id,
      reference_code,
      status_before,
      status_after,
      quantity_delta,
      available_delta,
      rented_delta,
      unavailable_delta,
      description
    )
    VALUES (
      detail_row.dress_id,
      detail_row.dress_variant_id,
      'RENTAL_CANCEL',
      p_rental_id,
      rental_row.rental_code,
      detail_row.previous_status,
      next_status,
      0,
      detail_row.quantity,
      -detail_row.quantity,
      0,
      'Stok ukuran dikembalikan setelah rental dibatalkan'
    );
  END LOOP;

  SELECT coalesce(sum(amount),0)
  INTO paid_amount
  FROM public.payments
  WHERE rental_id = p_rental_id
    AND payment_type <> 'REFUND';

  UPDATE public.rentals
  SET rental_status = 'Cancelled',
      status = 'Cancelled',
      cancellation_reason = p_reason,
      cancelled_at = p_cancelled_at
  WHERE id = p_rental_id;

  IF p_deposit_action = 'REFUND' AND paid_amount > 0 THEN
    INSERT INTO public.payments(
      payment_code,
      rental_id,
      payment_date,
      amount,
      payment_method,
      payment_type,
      notes,
      description
    )
    VALUES (
      next_business_code('payment'),
      p_rental_id,
      p_cancelled_at::date,
      paid_amount,
      'Cash',
      'REFUND',
      'Refund karena pembatalan',
      'Pengembalian DP'
    );

    UPDATE public.rentals
    SET payment_status = 'Refunded'
    WHERE id = p_rental_id;
  ELSIF p_deposit_action = 'FORFEIT' AND paid_amount > 0 THEN
    PERFORM post_two_line_journal(
      next_business_code('journal'),
      p_cancelled_at::date,
      'rental_cancellation',
      p_rental_id,
      'DP hangus: ' || p_reason,
      '202',
      '403',
      paid_amount
    );
  END IF;
END;
$$;

REVOKE ALL
ON FUNCTION public.cancel_rental(bigint,text,varchar,timestamptz)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.cancel_rental(bigint,text,varchar,timestamptz)
TO authenticated;

CREATE OR REPLACE FUNCTION public.process_return_transaction(
  p_rental_id bigint,
  p_return_date date,
  p_condition varchar,
  p_notes text DEFAULT NULL,
  p_late_rate numeric DEFAULT 0,
  p_damage_amount numeric DEFAULT 0,
  p_payment_amount numeric DEFAULT 0,
  p_payment_method varchar DEFAULT 'Cash'
)
RETURNS TABLE(
  return_id bigint,
  return_code varchar,
  penalty_id bigint,
  payment_id bigint,
  total_penalty numeric,
  rental_status varchar
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rental_row public.rentals%ROWTYPE;
  new_return public.returns%ROWTYPE;
  new_penalty public.penalties%ROWTYPE;
  new_payment public.penalty_payments%ROWTYPE;
  new_penalty_id bigint;
  new_payment_id bigint;
  late_days_value integer;
  late_amount numeric;
  total_amount numeric;
  damage_value numeric := greatest(coalesce(p_damage_amount,0),0);
  payment_value numeric := greatest(coalesce(p_payment_amount,0),0);
  detail_row record;
  mapped_condition varchar;
  next_status varchar;
BEGIN
  IF current_app_role() NOT IN ('admin','staff','accounting') THEN
    RAISE EXCEPTION 'Role tidak diizinkan memproses return';
  END IF;

  SELECT *
  INTO rental_row
  FROM public.rentals
  WHERE id = p_rental_id
  FOR UPDATE;

  IF rental_row.id IS NULL THEN
    RAISE EXCEPTION 'Rental tidak ditemukan';
  END IF;

  IF p_return_date IS NULL THEN
    RAISE EXCEPTION 'Tanggal pengembalian wajib diisi';
  END IF;

  IF p_condition NOT IN ('Baik','Kotor','Rusak Ringan','Rusak Berat','Hilang') THEN
    RAISE EXCEPTION 'Kondisi pengembalian tidak valid';
  END IF;

  IF coalesce(p_late_rate,0) < 0
    OR damage_value < 0
    OR payment_value < 0
  THEN
    RAISE EXCEPTION 'Nominal denda tidak boleh negatif';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.returns
    WHERE rental_id = p_rental_id
  ) THEN
    RAISE EXCEPTION 'Rental sudah memiliki pengembalian';
  END IF;

  IF coalesce(rental_row.rental_status, rental_row.status) IN ('Returned','Completed','Cancelled')
    OR rental_row.status IN ('Completed','Cancelled')
  THEN
    RAISE EXCEPTION 'Rental berstatus % tidak dapat dikembalikan',
      coalesce(rental_row.rental_status, rental_row.status);
  END IF;

  late_days_value := greatest(0, p_return_date - rental_row.return_due_date);
  late_amount := late_days_value * coalesce(p_late_rate,0);
  total_amount := late_amount + damage_value;

  IF payment_value > total_amount THEN
    RAISE EXCEPTION 'Pembayaran denda melebihi total denda';
  END IF;

  INSERT INTO public.returns(
    rental_id,
    return_date,
    condition,
    late_days,
    notes,
    late_rate,
    late_penalty,
    damage_amount,
    total_penalty,
    penalty_payment_status
  )
  VALUES (
    p_rental_id,
    p_return_date,
    p_condition,
    late_days_value,
    p_notes,
    coalesce(p_late_rate,0),
    late_amount,
    damage_value,
    total_amount,
    CASE
      WHEN total_amount = 0 THEN 'Paid'
      WHEN payment_value = 0 THEN 'Unpaid'
      WHEN payment_value < total_amount THEN 'Partially Paid'
      ELSE 'Paid'
    END
  )
  RETURNING * INTO new_return;

  mapped_condition := CASE p_condition
    WHEN 'Baik' THEN 'Good'
    ELSE p_condition
  END;

  FOR detail_row IN
    SELECT
      detail.dress_id,
      detail.dress_variant_id,
      detail.quantity,
      variant.status AS previous_status,
      variant.condition AS previous_condition,
      variant.quantity,
      variant.available_quantity,
      variant.rented_quantity,
      variant.unavailable_quantity,
      variant.size
    FROM public.rental_details detail
    JOIN public.dress_variants variant
      ON variant.id = detail.dress_variant_id
    WHERE detail.rental_id = p_rental_id
    FOR UPDATE OF variant
  LOOP
    IF detail_row.rented_quantity < detail_row.quantity THEN
      RAISE EXCEPTION 'Jumlah unit disewa tidak konsisten untuk varian %',
        detail_row.dress_variant_id;
    END IF;

    UPDATE public.dress_variants
    SET rented_quantity = rented_quantity - detail_row.quantity,
        available_quantity = available_quantity + CASE
          WHEN p_condition = 'Baik' AND detail_row.size <> 'UNKNOWN'
          THEN detail_row.quantity
          ELSE 0
        END,
        unavailable_quantity = unavailable_quantity + CASE
          WHEN p_condition = 'Baik' AND detail_row.size <> 'UNKNOWN'
          THEN 0
          ELSE detail_row.quantity
        END,
        condition = CASE
          WHEN detail_row.size = 'UNKNOWN' THEN 'Unknown Size'
          ELSE CASE
            WHEN quantity = detail_row.quantity THEN mapped_condition
            WHEN condition = mapped_condition THEN condition
            ELSE 'Mixed'
          END
        END,
        status = CASE
          WHEN available_quantity + CASE
            WHEN p_condition = 'Baik' AND detail_row.size <> 'UNKNOWN'
            THEN detail_row.quantity
            ELSE 0
          END > 0 THEN 'Available'
          WHEN rented_quantity - detail_row.quantity > 0 THEN 'Rented'
          WHEN detail_row.size = 'UNKNOWN' THEN 'Unknown Size'
          WHEN p_condition = 'Kotor' THEN 'Laundry'
          WHEN p_condition = 'Rusak Ringan' THEN 'Repair'
          ELSE 'Not Available'
        END,
        updated_at = now()
    WHERE id = detail_row.dress_variant_id
    RETURNING status INTO next_status;

    INSERT INTO public.dress_movements(
      dress_id,
      dress_variant_id,
      movement_type,
      reference_id,
      reference_code,
      status_before,
      status_after,
      quantity_delta,
      available_delta,
      rented_delta,
      unavailable_delta,
      description
    )
    VALUES (
      detail_row.dress_id,
      detail_row.dress_variant_id,
      'RETURN',
      new_return.id,
      new_return.return_code,
      detail_row.previous_status,
      next_status,
      0,
      CASE
        WHEN p_condition = 'Baik' AND detail_row.size <> 'UNKNOWN'
        THEN detail_row.quantity
        ELSE 0
      END,
      -detail_row.quantity,
      CASE
        WHEN p_condition = 'Baik' AND detail_row.size <> 'UNKNOWN'
        THEN 0
        ELSE detail_row.quantity
      END,
      'Unit ukuran kembali dari pengembalian'
    );
  END LOOP;

  IF total_amount > 0 THEN
    INSERT INTO public.penalties(
      return_id,
      penalty_type,
      amount,
      description
    )
    VALUES (
      new_return.id,
      CASE
        WHEN late_amount > 0 AND damage_value > 0 THEN 'Late Return & Damage'
        WHEN late_amount > 0 THEN 'Late Return'
        ELSE 'Damage'
      END,
      total_amount,
      'Denda pengembalian terintegrasi'
    )
    RETURNING * INTO new_penalty;

    new_penalty_id := new_penalty.id;

    IF payment_value > 0 THEN
      INSERT INTO public.penalty_payments(
        penalty_id,
        payment_date,
        amount,
        payment_method,
        description
      )
      VALUES (
        new_penalty.id,
        p_return_date,
        payment_value,
        p_payment_method,
        'Pembayaran denda saat pengembalian'
      )
      RETURNING * INTO new_payment;

      new_payment_id := new_payment.id;
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    new_return.id,
    new_return.return_code,
    new_penalty_id,
    new_payment_id,
    total_amount,
    'Completed'::varchar;
END;
$$;

REVOKE ALL
ON FUNCTION public.process_return_transaction(
  bigint,
  date,
  varchar,
  text,
  numeric,
  numeric,
  numeric,
  varchar
)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.process_return_transaction(
  bigint,
  date,
  varchar,
  text,
  numeric,
  numeric,
  numeric,
  varchar
)
TO authenticated;

DROP TRIGGER IF EXISTS apply_return_dress_status
ON public.returns;

DROP TRIGGER IF EXISTS record_dress_movement
ON public.dresses;

DROP VIEW IF EXISTS public.v_dress_inventory;

CREATE VIEW public.v_dress_inventory WITH (security_invoker = true) AS
SELECT
  variant.id AS dress_variant_id,
  model.id AS dress_id,
  model.dress_code,
  model.name,
  model.category_id,
  category.category_name,
  model.color,
  model.purchase_price,
  model.rental_price,
  model.supplier_id,
  supplier.name AS supplier_name,
  model.photo_url,
  model.description,
  variant.size,
  variant.quantity,
  variant.available_quantity,
  variant.rented_quantity,
  variant.unavailable_quantity,
  variant.condition,
  variant.status
FROM public.dress_variants variant
JOIN public.dresses model
  ON model.id = variant.dress_id
LEFT JOIN public.dress_categories category
  ON category.id = model.category_id
LEFT JOIN public.suppliers supplier
  ON supplier.id = model.supplier_id
WHERE model.is_active;

REVOKE ALL
ON public.v_dress_inventory
FROM PUBLIC, anon;

GRANT SELECT
ON public.v_dress_inventory
TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';