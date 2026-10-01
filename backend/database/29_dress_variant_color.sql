-- Move color from dress-model identity to the dress variant while preserving
-- historical details. Cross-color model merges from migration 24 remain
-- explicitly unverified until physical stocktake.
-- Run after 28_deposit_return_accounting.sql.

BEGIN;

LOCK TABLE public.dress_variants IN SHARE ROW EXCLUSIVE MODE;

ALTER TABLE public.dress_variants
  ADD COLUMN IF NOT EXISTS color varchar(50),
  ADD COLUMN IF NOT EXISTS normalized_color text
    GENERATED ALWAYS AS (upper(btrim(coalesce(color, '')))) STORED;

-- A cross-color merge in migration 24 collapsed stock and transaction lines
-- by model and size. Keep those balances intact but do not guess their color.

UPDATE public.dress_variants variant
SET color = 'UNVERIFIED'
FROM public.dress_model_merge_map mapping
JOIN public.dresses source
  ON source.id = mapping.source_dress_id
JOIN public.dresses target
  ON target.id = mapping.target_dress_id
WHERE variant.dress_id = mapping.target_dress_id
  AND variant.color IS NULL
  AND variant.normalized_size = upper(
    btrim(coalesce(nullif(source.size, ''), 'UNKNOWN'))
  )
  AND lower(btrim(coalesce(source.color, ''))) <>
    lower(btrim(coalesce(target.color, '')));

UPDATE public.dress_variants variant
SET color = coalesce(nullif(btrim(model.color), ''), 'Belum ditentukan')
FROM public.dresses model
WHERE model.id = variant.dress_id
  AND variant.color IS NULL;

ALTER TABLE public.dress_variants
  ALTER COLUMN color SET NOT NULL;

ALTER TABLE public.dress_variants
  DROP CONSTRAINT IF EXISTS dress_variants_dress_size_key,
  DROP CONSTRAINT IF EXISTS dress_variants_dress_normalized_size_key;

DROP INDEX IF EXISTS public.dress_variants_dress_normalized_size_backfill_uidx;

CREATE UNIQUE INDEX IF NOT EXISTS dress_variants_dress_size_color_uidx
  ON public.dress_variants(
    dress_id,
    normalized_size,
    normalized_color
  );

-- Create empty, selectable color variants from reviewed merge-map source
-- models. Existing aggregate balances remain on their UNVERIFIED variant.

INSERT INTO public.dress_variants(
  dress_id,
  size,
  color,
  quantity,
  available_quantity,
  rented_quantity,
  unavailable_quantity,
  condition,
  status
)
SELECT
  mapping.target_dress_id,
  coalesce(nullif(upper(btrim(source.size)), ''), 'UNKNOWN'),
  btrim(source.color),
  0,
  0,
  0,
  0,
  'Good',
  'Not Available'
FROM public.dress_model_merge_map mapping
JOIN public.dresses source
  ON source.id = mapping.source_dress_id
JOIN public.dresses target
  ON target.id = mapping.target_dress_id
WHERE nullif(btrim(source.color), '') IS NOT NULL
  AND lower(btrim(coalesce(source.color, ''))) <>
    lower(btrim(coalesce(target.color, '')))
  AND NOT EXISTS (
    SELECT 1
    FROM public.dress_variants existing
    WHERE existing.dress_id = mapping.target_dress_id
      AND existing.normalized_size = upper(
        btrim(coalesce(nullif(source.size, ''), 'UNKNOWN'))
      )
      AND existing.normalized_color = upper(btrim(source.color))
  );

CREATE OR REPLACE FUNCTION public.ensure_dress_variant(
  p_dress_id bigint,
  p_size varchar,
  p_color varchar
)
RETURNS SETOF public.dress_variants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  variant_row public.dress_variants%ROWTYPE;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff', 'accounting') THEN
    RAISE EXCEPTION 'Role Anda tidak memiliki akses mengelola varian dress';
  END IF;

  IF p_dress_id IS NULL
    OR nullif(upper(trim(p_size)), '') IS NULL
    OR nullif(trim(p_color), '') IS NULL
  THEN
    RAISE EXCEPTION 'Master dress, ukuran, dan warna wajib diisi';
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
    color,
    condition,
    status
  )
  SELECT
    p_dress_id,
    upper(trim(p_size)),
    trim(p_color),
    'Good',
    'Not Available'
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.dress_variants existing
    WHERE existing.dress_id = p_dress_id
      AND existing.normalized_size = upper(trim(p_size))
      AND existing.normalized_color = upper(trim(p_color))
  );

  SELECT variant.*
  INTO variant_row
  FROM public.dress_variants variant
  WHERE variant.dress_id = p_dress_id
    AND variant.normalized_size = upper(trim(p_size))
    AND variant.normalized_color = upper(trim(p_color))
  FOR UPDATE;

  RETURN NEXT variant_row;
END;
$$;

REVOKE ALL
ON FUNCTION public.ensure_dress_variant(bigint, varchar, varchar)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.ensure_dress_variant(bigint, varchar, varchar)
TO authenticated;

-- Compatibility for clients that have not yet started sending a color.

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
  model_color varchar;
BEGIN
  SELECT coalesce(nullif(btrim(color), ''), 'Belum ditentukan')
  INTO model_color
  FROM public.dresses
  WHERE id = p_dress_id
    AND is_active;

  IF model_color IS NULL THEN
    RAISE EXCEPTION 'Master dress tidak ditemukan atau sudah nonaktif';
  END IF;

  RETURN QUERY
  SELECT *
  FROM public.ensure_dress_variant(
    p_dress_id,
    p_size,
    model_color
  );
END;
$$;

REVOKE ALL
ON FUNCTION public.ensure_dress_variant(bigint, varchar)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.ensure_dress_variant(bigint, varchar)
TO authenticated;

CREATE OR REPLACE FUNCTION public.validate_rental_detail_color()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  variant_color varchar;
BEGIN
  SELECT color
  INTO variant_color
  FROM public.dress_variants
  WHERE id = NEW.dress_variant_id;

  IF variant_color IS NULL THEN
    RAISE EXCEPTION 'Varian dress tidak ditemukan';
  END IF;

  IF upper(btrim(variant_color)) = 'UNVERIFIED' THEN
    RAISE EXCEPTION 'Warna stok lama belum diverifikasi; lakukan stocktake sebelum disewakan';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL
ON FUNCTION public.validate_rental_detail_color()
FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS validate_rental_detail_color
ON public.rental_details;

CREATE TRIGGER validate_rental_detail_color
BEFORE INSERT OR UPDATE OF dress_variant_id
ON public.rental_details
FOR EACH ROW
EXECUTE FUNCTION public.validate_rental_detail_color();

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
  selected_color varchar := coalesce(
    nullif(btrim(p_color), ''),
    'Belum ditentukan'
  );
  total_value numeric;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff', 'accounting') THEN
    RAISE EXCEPTION 'Role Anda tidak memiliki akses membuat pembelian';
  END IF;

  IF p_supplier_id IS NULL OR p_purchase_date IS NULL THEN
    RAISE EXCEPTION 'Supplier dan tanggal pembelian wajib diisi';
  END IF;

  IF p_payment_status IS NULL
    OR p_payment_status NOT IN ('Paid', 'Unpaid')
    OR p_payment_method IS NULL
    OR p_payment_method NOT IN ('Cash', 'Transfer', 'E-Wallet')
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

  IF upper(selected_color) = 'UNVERIFIED' THEN
    RAISE EXCEPTION 'Warna UNVERIFIED hanya untuk histori stok lama';
  END IF;

  IF selected_dress_id IS NULL THEN
    IF nullif(trim(p_dress_name), '') IS NULL OR p_category_id IS NULL THEN
      RAISE EXCEPTION 'Nama dan kategori model dress baru wajib diisi';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.dresses model
      WHERE model.is_active
        AND lower(btrim(model.name)) = lower(btrim(p_dress_name))
        AND model.category_id = p_category_id
    ) THEN
      RAISE EXCEPTION 'Model dengan nama dan kategori tersebut sudah terdaftar; pilih model yang ada dan tambahkan varian';
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
      NULL,
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
    color,
    condition,
    status
  )
  SELECT
    selected_dress_id,
    upper(trim(p_size)),
    selected_color,
    'Good',
    'Not Available'
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.dress_variants existing
    WHERE existing.dress_id = selected_dress_id
      AND existing.normalized_size = upper(trim(p_size))
      AND existing.normalized_color = upper(trim(selected_color))
  );

  SELECT variant.*
  INTO variant_row
  FROM public.dress_variants variant
  WHERE variant.dress_id = selected_dress_id
    AND variant.normalized_size = upper(trim(p_size))
    AND variant.normalized_color = upper(trim(selected_color))
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
FROM PUBLIC, anon;

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

CREATE OR REPLACE VIEW public.v_dress_inventory
WITH (security_invoker = true) AS
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

NOTIFY pgrst, 'reload schema';

COMMIT;