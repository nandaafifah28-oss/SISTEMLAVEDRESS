-- Keep legacy return/accounting logic, but attach all new state changes to one
-- physical unit and derive inventory totals from dress_units.
-- Run after 33_unit_purchase_rental_flows.sql.

BEGIN;

LOCK TABLE
  public.dress_units,
  public.dress_variants,
  public.rental_details,
  public.dress_movements
IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
  IF to_regprocedure('public.cancel_rental(bigint,text,character varying,timestamp with time zone)') IS NOT NULL
    AND to_regprocedure('public.cancel_rental_aggregate_legacy(bigint,text,character varying,timestamp with time zone)') IS NULL
  THEN
    ALTER FUNCTION public.cancel_rental(bigint,text,varchar,timestamptz)
      RENAME TO cancel_rental_aggregate_legacy;
  END IF;

  IF to_regprocedure('public.process_return_transaction(bigint,date,character varying,text,numeric,numeric,numeric,character varying)') IS NOT NULL
    AND to_regprocedure('public.process_return_transaction_aggregate_legacy(bigint,date,character varying,text,numeric,numeric,numeric,character varying)') IS NULL
  THEN
    ALTER FUNCTION public.process_return_transaction(
      bigint,
      date,
      varchar,
      text,
      numeric,
      numeric,
      numeric,
      varchar
    ) RENAME TO process_return_transaction_aggregate_legacy;
  END IF;
END;
$$;

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
  detail_row record;
  unit_row public.dress_units%ROWTYPE;
  movement_id bigint;
BEGIN
  PERFORM public.cancel_rental_aggregate_legacy(
    p_rental_id,
    p_reason,
    p_deposit_action,
    p_cancelled_at
  );

  FOR detail_row IN
    SELECT
      detail.id AS detail_id,
      detail.dress_id,
      detail.dress_variant_id,
      detail.unit_id,
      rental.rental_code
    FROM public.rental_details detail
    JOIN public.rentals rental
      ON rental.id = detail.rental_id
    WHERE detail.rental_id = p_rental_id
  LOOP
    IF detail_row.unit_id IS NULL THEN
      RAISE EXCEPTION 'Detail rental % belum memiliki unit fisik', detail_row.detail_id;
    END IF;

    SELECT *
    INTO unit_row
    FROM public.dress_units
    WHERE id = detail_row.unit_id
    FOR UPDATE;

    IF unit_row.id IS NULL
      OR unit_row.variant_id <> detail_row.dress_variant_id
    THEN
      RAISE EXCEPTION 'Unit rental tidak cocok dengan varian';
    END IF;

    IF unit_row.status <> 'Rented' THEN
      RAISE EXCEPTION 'Unit % harus berstatus Rented sebelum pembatalan', unit_row.unit_code;
    END IF;

    UPDATE public.dress_units
    SET status = 'Available',
        updated_at = now()
    WHERE id = unit_row.id;

    SELECT movement.id
    INTO movement_id
    FROM public.dress_movements movement
    WHERE movement.reference_id = p_rental_id
      AND movement.movement_type = 'RENTAL_CANCEL'
      AND movement.dress_variant_id = detail_row.dress_variant_id
      AND movement.unit_id IS NULL
    ORDER BY movement.id
    LIMIT 1;

    IF movement_id IS NULL THEN
      RAISE EXCEPTION 'Movement pembatalan unit tidak ditemukan';
    END IF;

    UPDATE public.dress_movements
    SET unit_id = unit_row.id,
        status_before = 'Rented',
        status_after = 'Available',
        quantity_delta = 0,
        available_delta = 1,
        rented_delta = -1,
        unavailable_delta = 0,
        notes = 'Stok unit dikembalikan setelah rental dibatalkan'
    WHERE id = movement_id;
  END LOOP;
END;
$$;

REVOKE ALL
ON FUNCTION public.cancel_rental(bigint,text,varchar,timestamptz)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.cancel_rental(bigint,text,varchar,timestamptz)
TO authenticated;

REVOKE ALL
ON FUNCTION public.cancel_rental_aggregate_legacy(bigint,text,varchar,timestamptz)
FROM PUBLIC, anon, authenticated;

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
  result_row record;
  detail_row record;
  unit_row public.dress_units%ROWTYPE;
  variant_row public.dress_variants%ROWTYPE;
  unit_count integer;
  return_unit_id bigint;
  movement_id bigint;
  next_unit_status varchar;
  next_unit_condition varchar;
BEGIN
  SELECT *
  INTO result_row
  FROM public.process_return_transaction_aggregate_legacy(
    p_rental_id,
    p_return_date,
    p_condition,
    p_notes,
    p_late_rate,
    p_damage_amount,
    p_payment_amount,
    p_payment_method
  );

  IF result_row.return_id IS NULL THEN
    RAISE EXCEPTION 'Return tidak menghasilkan transaksi';
  END IF;

  next_unit_condition := CASE p_condition
    WHEN 'Baik' THEN 'Good'
    WHEN 'Kotor' THEN 'Fair'
    WHEN 'Rusak Ringan' THEN 'Damaged'
    ELSE 'Unusable'
  END;

  FOR detail_row IN
    SELECT
      detail.id AS detail_id,
      detail.dress_id,
      detail.dress_variant_id,
      detail.unit_id
    FROM public.rental_details detail
    WHERE detail.rental_id = p_rental_id
    ORDER BY detail.id
  LOOP
    IF detail_row.unit_id IS NULL THEN
      RAISE EXCEPTION 'Detail rental % belum memiliki unit fisik', detail_row.detail_id;
    END IF;

    SELECT *
    INTO unit_row
    FROM public.dress_units
    WHERE id = detail_row.unit_id
    FOR UPDATE;

    IF unit_row.id IS NULL
      OR unit_row.variant_id <> detail_row.dress_variant_id
      OR unit_row.status <> 'Rented'
    THEN
      RAISE EXCEPTION 'Unit rental tidak cocok atau bukan berstatus Rented';
    END IF;

    SELECT *
    INTO variant_row
    FROM public.dress_variants
    WHERE id = detail_row.dress_variant_id;

    next_unit_status := CASE
      WHEN p_condition = 'Baik' AND variant_row.size = 'UNKNOWN' THEN 'Not Available'
      WHEN p_condition = 'Baik' THEN 'Available'
      WHEN p_condition = 'Kotor' THEN 'Laundry'
      WHEN p_condition = 'Rusak Ringan' THEN 'Repair'
      ELSE 'Not Available'
    END;

    UPDATE public.dress_units
    SET status = next_unit_status,
        condition = next_unit_condition,
        notes = coalesce(nullif(trim(p_notes), ''), notes),
        updated_at = now()
    WHERE id = unit_row.id;

    SELECT movement.id
    INTO movement_id
    FROM public.dress_movements movement
    WHERE movement.reference_id = result_row.return_id
      AND movement.movement_type = 'RETURN'
      AND movement.dress_variant_id = detail_row.dress_variant_id
      AND movement.unit_id IS NULL
    ORDER BY movement.id
    LIMIT 1;

    IF movement_id IS NULL THEN
      RAISE EXCEPTION 'Movement return untuk unit tidak ditemukan';
    END IF;

    UPDATE public.dress_movements
    SET unit_id = unit_row.id,
        status_before = 'Rented',
        status_after = next_unit_status,
        quantity_delta = 0,
        available_delta = CASE
          WHEN next_unit_status = 'Available' THEN 1
          ELSE 0
        END,
        rented_delta = -1,
        unavailable_delta = CASE
          WHEN next_unit_status IN ('Laundry','Repair','Not Available') THEN 1
          ELSE 0
        END,
        description = coalesce(nullif(trim(p_notes), ''), description),
        notes = coalesce(nullif(trim(p_notes), ''), notes)
    WHERE id = movement_id;

    return_unit_id := unit_row.id;
  END LOOP;

  SELECT count(*)::integer
  INTO unit_count
  FROM public.rental_details
  WHERE rental_id = p_rental_id;

  IF unit_count = 1 THEN
    UPDATE public.returns
    SET unit_id = return_unit_id
    WHERE id = result_row.return_id;
  END IF;

  RETURN QUERY
  SELECT
    result_row.return_id,
    result_row.return_code,
    result_row.penalty_id,
    result_row.payment_id,
    result_row.total_penalty,
    result_row.rental_status;
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

REVOKE ALL
ON FUNCTION public.process_return_transaction_aggregate_legacy(
  bigint,
  date,
  varchar,
  text,
  numeric,
  numeric,
  numeric,
  varchar
)
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.update_dress_unit_status(
  p_unit_id bigint,
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
  unit_row public.dress_units%ROWTYPE;
  variant_row public.dress_variants%ROWTYPE;
  previous_unavailable integer;
  next_unavailable integer;
  next_variant_condition varchar;
  movement_code varchar;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION 'Role tidak diizinkan mengubah status unit';
  END IF;

  IF p_status IS NULL
    OR p_status NOT IN ('Available', 'Laundry', 'Repair', 'Not Available')
  THEN
    RAISE EXCEPTION 'Status unit tidak valid';
  END IF;

  IF p_condition IS NULL
    OR p_condition NOT IN ('Good', 'Fair', 'Damaged', 'Unusable')
  THEN
    RAISE EXCEPTION 'Kondisi unit tidak valid';
  END IF;

  IF nullif(trim(p_notes), '') IS NULL THEN
    RAISE EXCEPTION 'Catatan status wajib diisi';
  END IF;

  SELECT variant.*
  INTO variant_row
  FROM public.dress_variants variant
  JOIN public.dress_units unit
    ON unit.variant_id = variant.id
  WHERE unit.id = p_unit_id
  FOR UPDATE OF variant;

  IF variant_row.id IS NULL THEN
    RAISE EXCEPTION 'Unit tidak ditemukan';
  END IF;

  SELECT *
  INTO unit_row
  FROM public.dress_units
  WHERE id = p_unit_id
  FOR UPDATE;

  IF unit_row.status = 'Rented' THEN
    RAISE EXCEPTION 'Unit Rented hanya dapat berubah melalui return atau pembatalan rental';
  END IF;

  previous_unavailable := CASE
    WHEN unit_row.status IN ('Laundry','Repair','Not Available','Unclassified') THEN 1
    ELSE 0
  END;

  next_unavailable := CASE
    WHEN p_status IN ('Laundry','Repair','Not Available') THEN 1
    ELSE 0
  END;

  UPDATE public.dress_units
  SET status = p_status,
      condition = p_condition,
      notes = trim(p_notes),
      updated_at = now()
  WHERE id = p_unit_id;

  UPDATE public.dress_variants
  SET available_quantity = available_quantity
        - CASE WHEN unit_row.status = 'Available' THEN 1 ELSE 0 END
        + CASE WHEN p_status = 'Available' THEN 1 ELSE 0 END,
      laundry_quantity = laundry_quantity
        - CASE WHEN unit_row.status = 'Laundry' THEN 1 ELSE 0 END
        + CASE WHEN p_status = 'Laundry' THEN 1 ELSE 0 END,
      repair_quantity = repair_quantity
        - CASE WHEN unit_row.status = 'Repair' THEN 1 ELSE 0 END
        + CASE WHEN p_status = 'Repair' THEN 1 ELSE 0 END,
      not_available_quantity = not_available_quantity
        - CASE WHEN unit_row.status = 'Not Available' THEN 1 ELSE 0 END
        + CASE WHEN p_status = 'Not Available' THEN 1 ELSE 0 END,
      unclassified_quantity = unclassified_quantity
        - CASE WHEN unit_row.status = 'Unclassified' THEN 1 ELSE 0 END,
      updated_at = now()
  WHERE id = variant_row.id;

  SELECT CASE
    WHEN count(DISTINCT condition) = 1 THEN min(condition)
    ELSE 'Mixed'
  END
  INTO next_variant_condition
  FROM public.dress_units
  WHERE variant_id = variant_row.id;

  UPDATE public.dress_variants
  SET condition = next_variant_condition
  WHERE id = variant_row.id;

  movement_code := public.next_business_code('movement');

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
    variant_row.dress_id,
    variant_row.id,
    p_unit_id,
    'STATUS_CHANGE',
    p_unit_id,
    movement_code,
    'inventory',
    unit_row.status,
    p_status,
    0,
    CASE
      WHEN p_status = 'Available' THEN 1
      ELSE 0
    END - CASE
      WHEN unit_row.status = 'Available' THEN 1
      ELSE 0
    END,
    0,
    next_unavailable - previous_unavailable,
    trim(p_notes),
    trim(p_notes)
  );
END;
$$;

REVOKE ALL
ON FUNCTION public.update_dress_unit_status(bigint,varchar,varchar,text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.update_dress_unit_status(bigint,varchar,varchar,text)
TO authenticated;

REVOKE ALL
ON FUNCTION public.update_dress_variant_status(bigint,varchar,varchar,text)
FROM PUBLIC, anon, authenticated;

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
  selected_unit_ids bigint[];
  movement_ref varchar;
  available_units integer;
  laundry_units integer;
  repair_units integer;
  not_available_units integer;
  unclassified_units integer;
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

  PERFORM 1
  FROM public.dress_variants
  WHERE id IN (p_unverified_variant_id, p_target_variant_id)
  ORDER BY id
  FOR UPDATE;

  SELECT *
  INTO source_variant
  FROM public.dress_variants
  WHERE id = p_unverified_variant_id;

  SELECT *
  INTO target_variant
  FROM public.dress_variants
  WHERE id = p_target_variant_id;

  IF source_variant.id IS NULL OR target_variant.id IS NULL THEN
    RAISE EXCEPTION 'Varian tidak ditemukan';
  END IF;

  IF upper(source_variant.color) <> 'UNVERIFIED'
    OR upper(target_variant.color) = 'UNVERIFIED'
    OR source_variant.dress_id <> target_variant.dress_id
    OR source_variant.normalized_size <> target_variant.normalized_size
  THEN
    RAISE EXCEPTION 'Rekonsiliasi harus memindahkan stok antar warna pada model dan ukuran yang sama';
  END IF;

  IF source_variant.quantity - source_variant.rented_quantity < p_quantity THEN
    RAISE EXCEPTION 'Jumlah melebihi unit yang tidak sedang disewa';
  END IF;

  SELECT coalesce(
    array_agg(selected.id ORDER BY selected.id),
    ARRAY[]::bigint[]
  )
  INTO selected_unit_ids
  FROM (
    SELECT unit.id
    FROM public.dress_units unit
    WHERE unit.variant_id = p_unverified_variant_id
      AND unit.status <> 'Rented'
    ORDER BY unit.id
    LIMIT p_quantity
    FOR UPDATE
  ) selected;

  IF cardinality(selected_unit_ids) <> p_quantity THEN
    RAISE EXCEPTION 'Jumlah unit fisik tidak sesuai; rekonsiliasi counter dan unit sebelum stocktake warna';
  END IF;

  SELECT
    count(*) FILTER (
      WHERE unit.status = 'Available'
    )::integer,
    count(*) FILTER (
      WHERE unit.status = 'Laundry'
    )::integer,
    count(*) FILTER (
      WHERE unit.status = 'Repair'
    )::integer,
    count(*) FILTER (
      WHERE unit.status = 'Not Available'
    )::integer,
    count(*) FILTER (
      WHERE unit.status = 'Unclassified'
    )::integer
  INTO
    available_units,
    laundry_units,
    repair_units,
    not_available_units,
    unclassified_units
  FROM public.dress_units unit
  WHERE unit.id = ANY(selected_unit_ids);

  movement_ref := public.next_business_code('movement');

  UPDATE public.dress_units
  SET variant_id = p_target_variant_id,
      notes = trim(p_notes),
      updated_at = now()
  WHERE id = ANY(selected_unit_ids);

  UPDATE public.dress_variants
  SET quantity = quantity - p_quantity,
      available_quantity = available_quantity - available_units,
      laundry_quantity = laundry_quantity - laundry_units,
      repair_quantity = repair_quantity - repair_units,
      not_available_quantity = not_available_quantity - not_available_units,
      unclassified_quantity = unclassified_quantity - unclassified_units,
      updated_at = now()
  WHERE id = p_unverified_variant_id;

  UPDATE public.dress_variants
  SET quantity = quantity + p_quantity,
      available_quantity = available_quantity + available_units,
      laundry_quantity = laundry_quantity + laundry_units,
      repair_quantity = repair_quantity + repair_units,
      not_available_quantity = not_available_quantity + not_available_units,
      unclassified_quantity = unclassified_quantity + unclassified_units,
      updated_at = now()
  WHERE id = p_target_variant_id;

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
    SELECT
      source_variant.dress_id,
      p_unverified_variant_id,
      unit.id,
      'COLOR_RECONCILIATION',
      unit.id,
      movement_ref,
      'inventory',
      unit.status,
      unit.status,
      -1,
      CASE
        WHEN unit.status = 'Available' THEN -1
        ELSE 0
      END,
      0,
      CASE
        WHEN unit.status IN ('Laundry','Repair','Not Available','Unclassified') THEN -1
        ELSE 0
      END,
      trim(p_notes),
      trim(p_notes)
    FROM unnest(selected_unit_ids) AS selected_unit(id)
    JOIN public.dress_units unit
      ON unit.id = selected_unit.id

  UNION ALL

    SELECT
      target_variant.dress_id,
      p_target_variant_id,
      unit.id,
      'COLOR_RECONCILIATION',
      unit.id,
      movement_ref,
      'inventory',
      unit.status,
      unit.status,
      1,
      CASE
        WHEN unit.status = 'Available' THEN 1
        ELSE 0
      END,
      0,
      CASE
        WHEN unit.status IN ('Laundry','Repair','Not Available','Unclassified') THEN 1
        ELSE 0
      END,
      trim(p_notes),
      trim(p_notes)
    FROM unnest(selected_unit_ids) AS selected_unit(id)
    JOIN public.dress_units unit
      ON unit.id = selected_unit.id;
END;
$$;

REVOKE ALL
ON FUNCTION public.reconcile_legacy_variant_color(bigint,bigint,integer,text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.reconcile_legacy_variant_color(bigint,bigint,integer,text)
TO authenticated;

DROP VIEW IF EXISTS public.v_dress_inventory;

CREATE VIEW public.v_dress_inventory WITH (security_invoker = true) AS
SELECT
  dress_variant_id,
  dress_id,
  dress_code,
  name,
  category_id,
  category_name,
  color,
  purchase_price,
  rental_price,
  supplier_id,
  supplier_name,
  photo_url,
  description,
  size,
  quantity,
  available_quantity,
  rented_quantity,
  unavailable_quantity,
  condition,
  status,
  laundry_quantity,
  repair_quantity,
  not_available_quantity,
  unclassified_quantity
FROM (
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
    coalesce(unit_counts.quantity, 0) AS quantity,
    coalesce(unit_counts.available_quantity, 0) AS available_quantity,
    coalesce(unit_counts.rented_quantity, 0) AS rented_quantity,
    coalesce(unit_counts.unavailable_quantity, 0) AS unavailable_quantity,
    coalesce(unit_counts.condition, variant.condition)::varchar(30) AS condition,
    CASE
      WHEN coalesce(unit_counts.unclassified_count, 0) > 0 THEN 'Unclassified'
      WHEN coalesce(unit_counts.available_count, 0) > 0
        AND coalesce(unit_counts.unavailable_count, 0)
          + coalesce(unit_counts.rented_count, 0) > 0
      THEN 'Mixed'
      WHEN coalesce(unit_counts.available_count, 0) > 0 THEN 'Available'
      WHEN coalesce(unit_counts.rented_count, 0) > 0
        AND coalesce(unit_counts.unavailable_count, 0) > 0
      THEN 'Mixed'
      WHEN coalesce(unit_counts.rented_count, 0) > 0 THEN 'Rented'
      WHEN coalesce(unit_counts.laundry_quantity, 0) > 0 THEN 'Laundry'
      WHEN coalesce(unit_counts.repair_quantity, 0) > 0 THEN 'Repair'
      ELSE 'Not Available'
    END::varchar(30) AS status,
    coalesce(unit_counts.laundry_quantity, 0) AS laundry_quantity,
    coalesce(unit_counts.repair_quantity, 0) AS repair_quantity,
    coalesce(unit_counts.not_available_quantity, 0) AS not_available_quantity,
    coalesce(unit_counts.unclassified_quantity, 0) AS unclassified_quantity
  FROM public.dress_variants variant
  JOIN public.dresses model
    ON model.id = variant.dress_id
  LEFT JOIN public.dress_categories category
    ON category.id = model.category_id
  LEFT JOIN public.suppliers supplier
    ON supplier.id = model.supplier_id
  LEFT JOIN (
    SELECT
      unit.variant_id,
      count(*)::integer AS quantity,
      count(*) FILTER (
        WHERE unit.status = 'Available'
      )::integer AS available_quantity,
      count(*) FILTER (
        WHERE unit.status = 'Rented'
      )::integer AS rented_quantity,
      count(*) FILTER (
        WHERE unit.status IN ('Laundry','Repair','Not Available','Unclassified')
      )::integer AS unavailable_quantity,
      count(*) FILTER (
        WHERE unit.status = 'Laundry'
      )::integer AS laundry_quantity,
      count(*) FILTER (
        WHERE unit.status = 'Repair'
      )::integer AS repair_quantity,
      count(*) FILTER (
        WHERE unit.status = 'Not Available'
      )::integer AS not_available_quantity,
      count(*) FILTER (
        WHERE unit.status = 'Unclassified'
      )::integer AS unclassified_quantity,
      CASE
        WHEN count(DISTINCT unit.condition) = 1 THEN min(unit.condition)
        ELSE 'Mixed'
      END AS condition,
      count(*) FILTER (
        WHERE unit.status = 'Available'
      ) AS available_count,
      count(*) FILTER (
        WHERE unit.status = 'Rented'
      ) AS rented_count,
      count(*) FILTER (
        WHERE unit.status IN ('Laundry','Repair','Not Available','Unclassified')
      ) AS unavailable_count,
      count(*) FILTER (
        WHERE unit.status = 'Unclassified'
      ) AS unclassified_count
    FROM public.dress_units unit
    GROUP BY unit.variant_id
  ) unit_counts
    ON unit_counts.variant_id = variant.id
  WHERE model.is_active
) inventory;

REVOKE ALL
ON public.v_dress_inventory
FROM PUBLIC, anon;

GRANT SELECT
ON public.v_dress_inventory
TO authenticated;

REVOKE INSERT, UPDATE, DELETE
ON public.dress_units
FROM authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;