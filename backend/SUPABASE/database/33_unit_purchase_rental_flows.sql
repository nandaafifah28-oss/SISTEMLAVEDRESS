-- Make purchase and rental transactions create/move individual physical units.
-- Run after 32_dress_physical_units.sql.

BEGIN;

CREATE OR REPLACE FUNCTION public.record_purchase_inventory_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  purchase_code_value varchar;
  variant_row public.dress_variants%ROWTYPE;
  unit_row public.dress_units%ROWTYPE;
  unit_number integer;
BEGIN
  SELECT purchase_code
  INTO purchase_code_value
  FROM public.purchases
  WHERE id = NEW.purchase_id;

  IF purchase_code_value IS NULL THEN
    RAISE EXCEPTION 'Purchase tidak ditemukan';
  END IF;

  SELECT *
  INTO variant_row
  FROM public.dress_variants
  WHERE id = NEW.dress_variant_id
  FOR UPDATE;

  IF variant_row.id IS NULL OR variant_row.dress_id IS DISTINCT FROM NEW.dress_id THEN
    RAISE EXCEPTION 'Varian pembelian tidak sesuai dengan model dress';
  END IF;

  UPDATE public.dress_variants
  SET quantity = quantity + NEW.quantity,
      available_quantity = available_quantity + NEW.quantity,
      condition = CASE
        WHEN quantity = 0 THEN 'Good'
        WHEN condition = 'Good' THEN 'Good'
        ELSE 'Mixed'
      END,
      updated_at = now()
  WHERE id = NEW.dress_variant_id;

  FOR unit_number IN 1..NEW.quantity LOOP
    INSERT INTO public.dress_units(
      variant_id,
      unit_code,
      status,
      condition,
      notes
    )
    VALUES (
      NEW.dress_variant_id,
      'UNIT-' || lpad(nextval('public.dress_unit_number_seq')::text, 8, '0'),
      'Available',
      'Good',
      'Unit dibuat dari purchase ' || purchase_code_value
    )
    RETURNING * INTO unit_row;

    INSERT INTO public.dress_movements(
      dress_id,
      dress_variant_id,
      unit_id,
      movement_type,
      reference_id,
      reference_code,
      reference_type,
      status_before,
      status_after,
      quantity_delta,
      available_delta,
      rented_delta,
      unavailable_delta,
      description,
      notes
    )
    VALUES (
      NEW.dress_id,
      NEW.dress_variant_id,
      unit_row.id,
      'PURCHASE_IN',
      NEW.purchase_id,
      purchase_code_value,
      'purchase',
      NULL,
      'Available',
      1,
      1,
      0,
      0,
      'Unit fisik masuk melalui pembelian',
      'Unit fisik masuk melalui pembelian'
    );
  END LOOP;

  RETURN NEW;
END;
$$;

REVOKE ALL
ON FUNCTION public.record_purchase_inventory_movement()
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.create_rental_unit_transaction(
  p_customer_id bigint,
  p_dress_id bigint,
  p_dress_variant_id bigint,
  p_dress_unit_id bigint,
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
  unit_id bigint,
  unit_code varchar,
  payment_code varchar
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_rental public.rentals%ROWTYPE;
  variant_row public.dress_variants%ROWTYPE;
  unit_row public.dress_units%ROWTYPE;
  new_payment_code varchar;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff', 'accounting') THEN
    RAISE EXCEPTION 'Role Anda tidak memiliki akses membuat rental';
  END IF;

  IF p_customer_id IS NULL
    OR p_dress_id IS NULL
    OR p_dress_variant_id IS NULL
    OR p_dress_unit_id IS NULL
  THEN
    RAISE EXCEPTION 'Customer, dress, varian, dan unit wajib dipilih';
  END IF;

  IF p_rental_date IS NULL
    OR p_return_due_date IS NULL
    OR p_return_due_date < p_rental_date
  THEN
    RAISE EXCEPTION 'Tanggal rental tidak valid';
  END IF;

  IF p_total_rental IS NULL
    OR p_total_rental < 0
    OR p_payment_amount IS NULL
    OR coalesce(p_deposit_amount, 0) < 0
    OR coalesce(p_payment_amount, 0) < 0
  THEN
    RAISE EXCEPTION 'Nominal rental/deposit/pembayaran tidak valid';
  END IF;

  IF p_payment_amount > p_total_rental THEN
    RAISE EXCEPTION 'Pembayaran melebihi total sewa';
  END IF;

  IF p_rental_status IS NULL OR p_rental_status NOT IN ('Booked', 'Ongoing') THEN
    RAISE EXCEPTION 'Status rental tidak valid';
  END IF;

  IF p_payment_amount > 0
    AND (
      p_payment_method IS NULL
      OR p_payment_method NOT IN (
        'Cash',
        'Transfer',
        'Transfer Bank',
        'E-Wallet',
        'QRIS',
        'Lainnya'
      )
    )
  THEN
    RAISE EXCEPTION 'Metode pembayaran tidak valid';
  END IF;

  IF p_payment_type IS NULL OR p_payment_type NOT IN ('DP', 'PELUNASAN') THEN
    RAISE EXCEPTION 'Tipe pembayaran rental tidak valid';
  END IF;

  SELECT *
  INTO variant_row
  FROM public.dress_variants
  WHERE id = p_dress_variant_id
    AND dress_id = p_dress_id
  FOR UPDATE;

  IF variant_row.id IS NULL THEN
    RAISE EXCEPTION 'Varian tidak sesuai dengan model dress';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.dresses
    WHERE id = p_dress_id
      AND is_active
  ) THEN
    RAISE EXCEPTION 'Master dress tidak ditemukan atau sudah nonaktif';
  END IF;

  SELECT *
  INTO unit_row
  FROM public.dress_units
  WHERE id = p_dress_unit_id
    AND variant_id = p_dress_variant_id
    AND status = 'Available'
  FOR UPDATE;

  IF unit_row.id IS NULL THEN
    RAISE EXCEPTION 'Unit tidak tersedia; pilih unit berstatus Available';
  END IF;

  IF variant_row.available_quantity <= 0 THEN
    RAISE EXCEPTION 'Varian tidak memiliki stok tersedia';
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
    coalesce(p_rental_code, public.next_business_code('rental')),
    p_customer_id,
    p_rental_date,
    p_return_due_date,
    p_total_rental,
    p_total_rental,
    coalesce(p_deposit_amount, 0),
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
    unit_id,
    rental_price,
    quantity,
    subtotal
  )
  VALUES (
    new_rental.id,
    p_dress_id,
    p_dress_variant_id,
    unit_row.id,
    p_total_rental,
    1,
    p_total_rental
  );

  UPDATE public.dress_units
  SET status = 'Rented',
      updated_at = now()
  WHERE id = unit_row.id;

  UPDATE public.dress_variants
  SET available_quantity = available_quantity - 1,
      rented_quantity = rented_quantity + 1,
      updated_at = now()
  WHERE id = p_dress_variant_id;

  INSERT INTO public.dress_movements(
    dress_id,
    dress_variant_id,
    unit_id,
    movement_type,
    reference_id,
    reference_code,
    reference_type,
    status_before,
    status_after,
    quantity_delta,
    available_delta,
    rented_delta,
    unavailable_delta,
    description,
    notes
  )
  VALUES (
    p_dress_id,
    p_dress_variant_id,
    unit_row.id,
    'RENTAL_OUT',
    new_rental.id,
    new_rental.rental_code,
    'rental',
    'Available',
    'Rented',
    0,
    -1,
    1,
    0,
    'Unit fisik keluar untuk penyewaan',
    'Unit fisik keluar untuk penyewaan'
  );

  IF p_payment_amount > 0 THEN
    new_payment_code := public.next_business_code('payment');

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
    unit_row.id,
    unit_row.unit_code,
    new_payment_code;
END;
$$;

REVOKE ALL
ON FUNCTION public.create_rental_unit_transaction(
  bigint,
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
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.create_rental_unit_transaction(
  bigint,
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

-- Keep the previous RPC signature working, but always reserve a concrete unit.

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
  chosen_unit_id bigint;
  result_row record;
BEGIN
  SELECT id
  INTO chosen_unit_id
  FROM public.dress_units
  WHERE variant_id = p_dress_variant_id
    AND status = 'Available'
  ORDER BY id
  LIMIT 1;

  IF chosen_unit_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ada unit Available untuk varian ini';
  END IF;

  SELECT *
  INTO result_row
  FROM public.create_rental_unit_transaction(
    p_customer_id,
    p_dress_id,
    p_dress_variant_id,
    chosen_unit_id,
    p_rental_date,
    p_return_due_date,
    p_total_rental,
    p_rental_code,
    p_deposit_amount,
    p_rental_status,
    p_payment_amount,
    p_payment_date,
    p_payment_method,
    p_payment_type
  );

  RETURN QUERY
  SELECT
    result_row.rental_id,
    result_row.rental_code,
    result_row.payment_code;
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
FROM PUBLIC, anon;

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

REVOKE INSERT, UPDATE, DELETE
ON public.dress_units
FROM authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;