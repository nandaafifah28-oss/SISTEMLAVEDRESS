-- Track inventory condition/status quantities per dress-size-color variant.
-- Run after 29_dress_variant_color.sql.

BEGIN;

ALTER TABLE public.dress_variants
  ADD COLUMN IF NOT EXISTS laundry_quantity integer NOT NULL DEFAULT 0 CHECK (laundry_quantity >= 0),
  ADD COLUMN IF NOT EXISTS repair_quantity integer NOT NULL DEFAULT 0 CHECK (repair_quantity >= 0),
  ADD COLUMN IF NOT EXISTS not_available_quantity integer NOT NULL DEFAULT 0 CHECK (not_available_quantity >= 0),
  ADD COLUMN IF NOT EXISTS unclassified_quantity integer NOT NULL DEFAULT 0 CHECK (unclassified_quantity >= 0);

-- Old aggregate unavailable stock has no per-condition count. Preserve it,
-- classify only what the old status proves, and leave mixed rows explicit.

UPDATE public.dress_variants
SET laundry_quantity = CASE
      WHEN lower(status) = 'laundry' THEN unavailable_quantity
      ELSE 0
    END,
    repair_quantity = CASE
      WHEN lower(status) = 'repair' THEN unavailable_quantity
      ELSE 0
    END,
    not_available_quantity = CASE
      WHEN lower(status) IN ('not available', 'unknown size') THEN unavailable_quantity
      ELSE 0
    END,
    unclassified_quantity = CASE
      WHEN lower(status) IN ('available', 'rented', 'mixed', 'unknown size')
        AND lower(status) <> 'unknown size'
      THEN unavailable_quantity
      ELSE 0
    END
WHERE unavailable_quantity > 0
  AND laundry_quantity = 0
  AND repair_quantity = 0
  AND not_available_quantity = 0
  AND unclassified_quantity = 0;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.dress_variants'::regclass
      AND conname = 'dress_variants_unavailable_breakdown_check'
  ) THEN
    ALTER TABLE public.dress_variants
      ADD CONSTRAINT dress_variants_unavailable_breakdown_check
      CHECK (
        unavailable_quantity = laundry_quantity
          + repair_quantity
          + not_available_quantity
          + unclassified_quantity
      );
  END IF;
END;
$$;

ALTER TABLE public.dress_movements
  ADD COLUMN IF NOT EXISTS reference_type varchar(30);

UPDATE public.dress_movements
SET reference_type = CASE
  WHEN movement_type IN ('PURCHASE_IN', 'PURCHASE') THEN 'purchase'
  WHEN movement_type IN ('RENTAL_OUT', 'RENTAL_CANCEL') THEN 'rental'
  WHEN movement_type = 'RETURN' THEN 'return'
  WHEN movement_type IN ('STATUS_CHANGE', 'COLOR_RECONCILIATION') THEN 'inventory'
  ELSE lower(movement_type)
END
WHERE reference_type IS NULL;

CREATE OR REPLACE FUNCTION public.derive_dress_variant_status()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.unavailable_quantity := NEW.laundry_quantity
    + NEW.repair_quantity
    + NEW.not_available_quantity
    + NEW.unclassified_quantity;

  NEW.status := CASE
    WHEN NEW.unclassified_quantity > 0 THEN 'Unclassified'
    WHEN NEW.available_quantity > 0
      AND (NEW.rented_quantity + NEW.unavailable_quantity) > 0
    THEN 'Mixed'
    WHEN NEW.available_quantity > 0 THEN 'Available'
    WHEN NEW.rented_quantity > 0
      AND NEW.unavailable_quantity > 0
    THEN 'Mixed'
    WHEN NEW.rented_quantity > 0 THEN 'Rented'
    WHEN NEW.laundry_quantity > 0 THEN 'Laundry'
    WHEN NEW.repair_quantity > 0 THEN 'Repair'
    ELSE 'Not Available'
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS derive_dress_variant_status
ON public.dress_variants;

CREATE TRIGGER derive_dress_variant_status
BEFORE INSERT OR UPDATE OF
  quantity,
  available_quantity,
  rented_quantity,
  unavailable_quantity,
  laundry_quantity,
  repair_quantity,
  not_available_quantity,
  unclassified_quantity
ON public.dress_variants
FOR EACH ROW
EXECUTE FUNCTION public.derive_dress_variant_status();

REVOKE ALL
ON FUNCTION public.derive_dress_variant_status()
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.set_dress_movement_reference_type()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.reference_type IS NULL THEN
    NEW.reference_type := CASE
      WHEN NEW.movement_type IN ('PURCHASE_IN', 'PURCHASE') THEN 'purchase'
      WHEN NEW.movement_type IN ('RENTAL_OUT', 'RENTAL_CANCEL') THEN 'rental'
      WHEN NEW.movement_type = 'RETURN' THEN 'return'
      WHEN NEW.movement_type IN ('STATUS_CHANGE', 'COLOR_RECONCILIATION') THEN 'inventory'
      ELSE lower(NEW.movement_type)
    END;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_dress_movement_reference_type
ON public.dress_movements;

CREATE TRIGGER set_dress_movement_reference_type
BEFORE INSERT
ON public.dress_movements
FOR EACH ROW
EXECUTE FUNCTION public.set_dress_movement_reference_type();

REVOKE ALL
ON FUNCTION public.set_dress_movement_reference_type()
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_dress_variant_status(
  p_dress_variant_id bigint,
  p_status varchar,
  p_condition varchar,
  p_notes text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  variant_row public.dress_variants%ROWTYPE;
  next_status varchar;
  next_available integer;
  next_laundry integer;
  next_repair integer;
  next_not_available integer;
  previous_unavailable integer;
  next_unavailable integer;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION 'Role tidak diizinkan mengubah status persediaan';
  END IF;

  IF p_status IS NULL
    OR p_status NOT IN ('Available', 'Laundry', 'Repair', 'Not Available')
  THEN
    RAISE EXCEPTION 'Status persediaan tidak valid';
  END IF;

  IF p_condition IS NULL
    OR p_condition NOT IN ('Good', 'Mixed', 'Dirty', 'Damaged', 'Unusable')
  THEN
    RAISE EXCEPTION 'Kondisi persediaan tidak valid';
  END IF;

  IF nullif(trim(p_notes), '') IS NULL THEN
    RAISE EXCEPTION 'Catatan perubahan status wajib diisi';
  END IF;

  SELECT *
  INTO variant_row
  FROM public.dress_variants
  WHERE id = p_dress_variant_id
  FOR UPDATE;

  IF variant_row.id IS NULL THEN
    RAISE EXCEPTION 'Varian dress tidak ditemukan';
  END IF;

  IF variant_row.rented_quantity > 0 THEN
    RAISE EXCEPTION 'Varian masih memiliki unit yang disewa; ubah status setelah return';
  END IF;

  IF variant_row.quantity <= 0 THEN
    RAISE EXCEPTION 'Varian belum memiliki stok';
  END IF;

  previous_unavailable := variant_row.unavailable_quantity;

  next_available := CASE
    WHEN p_status = 'Available' THEN variant_row.quantity
    ELSE 0
  END;

  next_laundry := CASE
    WHEN p_status = 'Laundry' THEN variant_row.quantity
    ELSE 0
  END;

  next_repair := CASE
    WHEN p_status = 'Repair' THEN variant_row.quantity
    ELSE 0
  END;

  next_not_available := CASE
    WHEN p_status = 'Not Available' THEN variant_row.quantity
    ELSE 0
  END;

  next_unavailable := next_laundry + next_repair + next_not_available;

  UPDATE public.dress_variants
  SET available_quantity = next_available,
      laundry_quantity = next_laundry,
      repair_quantity = next_repair,
      not_available_quantity = next_not_available,
      unclassified_quantity = 0,
      condition = p_condition,
      updated_at = now()
  WHERE id = p_dress_variant_id
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
    variant_row.dress_id,
    variant_row.id,
    'STATUS_CHANGE',
    variant_row.id,
    'INV-' || variant_row.id::text,
    variant_row.status,
    next_status,
    0,
    next_available - variant_row.available_quantity,
    0,
    next_unavailable - previous_unavailable,
    trim(p_notes)
  );
END;
$$;

REVOKE ALL
ON FUNCTION public.update_dress_variant_status(bigint, varchar, varchar, text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.update_dress_variant_status(bigint, varchar, varchar, text)
TO authenticated;

CREATE OR REPLACE FUNCTION public.reconcile_legacy_variant_color(
  p_unverified_variant_id bigint,
  p_target_variant_id bigint,
  p_quantity integer,
  p_notes text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  source_variant public.dress_variants%ROWTYPE;
  target_variant public.dress_variants%ROWTYPE;
  movement_ref varchar;
BEGIN
  IF current_app_role() <> 'admin' THEN
    RAISE EXCEPTION 'Hanya admin yang dapat merekonsiliasi warna stok';
  END IF;

  IF p_quantity IS NULL
    OR p_quantity <= 0
    OR nullif(trim(p_notes), '') IS NULL
  THEN
    RAISE EXCEPTION 'Jumlah dan catatan stocktake wajib diisi';
  END IF;

  SELECT *
  INTO source_variant
  FROM public.dress_variants
  WHERE id = p_unverified_variant_id
  FOR UPDATE;

  SELECT *
  INTO target_variant
  FROM public.dress_variants
  WHERE id = p_target_variant_id
  FOR UPDATE;

  IF source_variant.id IS NULL OR target_variant.id IS NULL THEN
    RAISE EXCEPTION 'Varian tidak ditemukan';
  END IF;

  IF upper(source_variant.color) <> 'UNVERIFIED'
    OR target_variant.color = 'UNVERIFIED'
    OR source_variant.dress_id <> target_variant.dress_id
    OR source_variant.normalized_size <> target_variant.normalized_size
  THEN
    RAISE EXCEPTION 'Rekonsiliasi harus memindahkan stok antar warna pada model dan ukuran yang sama';
  END IF;

  IF source_variant.available_quantity < p_quantity THEN
    RAISE EXCEPTION 'Jumlah melebihi stok tersedia yang belum terpetakan';
  END IF;

  movement_ref := public.next_business_code('movement');

  UPDATE public.dress_variants
  SET quantity = quantity - p_quantity,
      available_quantity = available_quantity - p_quantity,
      updated_at = now()
  WHERE id = source_variant.id;

  UPDATE public.dress_variants
  SET quantity = quantity + p_quantity,
      available_quantity = available_quantity + p_quantity,
      updated_at = now()
  WHERE id = target_variant.id;

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
  VALUES
    (
      source_variant.dress_id,
      source_variant.id,
      'COLOR_RECONCILIATION',
      source_variant.id,
      movement_ref,
      source_variant.status,
      source_variant.status,
      -p_quantity,
      -p_quantity,
      0,
      0,
      trim(p_notes)
    ),
    (
      target_variant.dress_id,
      target_variant.id,
      'COLOR_RECONCILIATION',
      target_variant.id,
      movement_ref,
      target_variant.status,
      target_variant.status,
      p_quantity,
      p_quantity,
      0,
      0,
      trim(p_notes)
    );
END;
$$;

REVOKE ALL
ON FUNCTION public.reconcile_legacy_variant_color(bigint, bigint, integer, text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.reconcile_legacy_variant_color(bigint, bigint, integer, text)
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
  deposit_value numeric;
  deposit_used_value numeric;
  deposit_refunded_value numeric;
  customer_receivable_value numeric;
  damage_value numeric := greatest(coalesce(p_damage_amount, 0), 0);
  payment_value numeric := greatest(coalesce(p_payment_amount, 0), 0);
  detail_row record;
  mapped_condition varchar;
  next_status varchar;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff', 'accounting') THEN
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

  IF p_condition IS NULL
    OR p_condition NOT IN ('Baik', 'Kotor', 'Rusak Ringan', 'Rusak Berat', 'Hilang')
  THEN
    RAISE EXCEPTION 'Kondisi pengembalian tidak valid';
  END IF;

  IF coalesce(p_late_rate, 0) < 0
    OR coalesce(p_damage_amount, 0) < 0
    OR coalesce(p_payment_amount, 0) < 0
  THEN
    RAISE EXCEPTION 'Nominal denda tidak boleh negatif';
  END IF;

  IF payment_value > 0
    AND (
      p_payment_method IS NULL
      OR p_payment_method NOT IN ('Cash', 'Transfer', 'E-Wallet')
    )
  THEN
    RAISE EXCEPTION 'Metode pembayaran denda tidak valid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.returns
    WHERE rental_id = p_rental_id
  ) THEN
    RAISE EXCEPTION 'Rental sudah memiliki pengembalian';
  END IF;

  IF coalesce(rental_row.rental_status, rental_row.status) IN ('Returned', 'Completed', 'Cancelled')
    OR rental_row.status IN ('Completed', 'Cancelled')
  THEN
    RAISE EXCEPTION 'Rental berstatus % tidak dapat dikembalikan',
      coalesce(rental_row.rental_status, rental_row.status);
  END IF;

  late_days_value := greatest(0, p_return_date - rental_row.return_due_date);
  late_amount := late_days_value * coalesce(p_late_rate, 0);
  total_amount := late_amount + damage_value;
  deposit_value := coalesce(rental_row.deposit_received_amount, 0);
  deposit_used_value := least(deposit_value, total_amount);
  deposit_refunded_value := greatest(deposit_value - total_amount, 0);
  customer_receivable_value := greatest(total_amount - deposit_used_value, 0);

  IF payment_value > customer_receivable_value THEN
    RAISE EXCEPTION 'Pembayaran melebihi sisa denda setelah deposit';
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
    penalty_payment_status,
    deposit_used,
    deposit_refunded,
    customer_receivable
  )
  VALUES (
    p_rental_id,
    p_return_date,
    p_condition,
    late_days_value,
    p_notes,
    coalesce(p_late_rate, 0),
    late_amount,
    damage_value,
    total_amount,
    CASE
      WHEN customer_receivable_value = 0
        OR payment_value >= customer_receivable_value
      THEN 'Paid'
      WHEN payment_value = 0 THEN 'Unpaid'
      ELSE 'Partially Paid'
    END,
    deposit_used_value,
    deposit_refunded_value,
    customer_receivable_value
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
        laundry_quantity = laundry_quantity + CASE
          WHEN p_condition = 'Kotor' AND detail_row.size <> 'UNKNOWN'
          THEN detail_row.quantity
          ELSE 0
        END,
        repair_quantity = repair_quantity + CASE
          WHEN p_condition = 'Rusak Ringan' AND detail_row.size <> 'UNKNOWN'
          THEN detail_row.quantity
          ELSE 0
        END,
        not_available_quantity = not_available_quantity + CASE
          WHEN p_condition IN ('Rusak Berat', 'Hilang')
            OR detail_row.size = 'UNKNOWN'
          THEN detail_row.quantity
          ELSE 0
        END,
        condition = CASE
          WHEN detail_row.size = 'UNKNOWN' THEN 'Unknown Size'
          ELSE CASE
            WHEN quantity = detail_row.quantity THEN mapped_condition
            WHEN condition = mapped_condition THEN condition
            ELSE 'Mixed'
          END
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
        'Pembayaran sisa denda saat pengembalian'
      )
      RETURNING * INTO new_payment;

      new_payment_id := new_payment.id;
    END IF;
  END IF;

  IF deposit_refunded_value > 0 THEN
    PERFORM public.post_two_line_journal(
      public.next_business_code('journal'),
      p_return_date,
      'deposit_refund',
      new_return.id,
      'Pengembalian sisa deposit ' || rental_row.rental_code,
      '202',
      '101',
      deposit_refunded_value
    );
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
FROM PUBLIC, anon;

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

CREATE OR REPLACE VIEW public.v_dress_inventory WITH (security_invoker = true) AS
SELECT
  variant.id AS dress_variant_id,
  model.id AS dress_id,
  model.dress_code,
  model.name,
  model.category_id,
  category.category_name,
  variant.color,
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
  variant.status,
  variant.laundry_quantity,
  variant.repair_quantity,
  variant.not_available_quantity,
  variant.unclassified_quantity
FROM public.dress_variants variant
JOIN public.dresses model
  ON model.id = variant.dress_id
LEFT JOIN public.dress_categories category
  ON category.id = model.category_id
LEFT JOIN public.suppliers supplier
  ON supplier.id = model.supplier_id
WHERE model.is_active;

NOTIFY pgrst, 'reload schema';

COMMIT;