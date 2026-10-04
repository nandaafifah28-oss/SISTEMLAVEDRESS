-- Fix PL/pgSQL output-column ambiguity in the purchase transaction RPC.
-- Run after 26_dress_photo_storage.sql.

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
RETURNS TABLE(purchase_id bigint, purchase_code varchar, dress_id bigint)
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
    FROM public.dress_variants AS existing
    WHERE existing.dress_id = selected_dress_id
      AND existing.normalized_size = upper(trim(p_size))
  );

  SELECT variant.*
  INTO variant_row
  FROM public.dress_variants AS variant
  WHERE variant.dress_id = selected_dress_id
    AND variant.normalized_size = upper(trim(p_size))
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
  SELECT purchase_row.id, purchase_row.purchase_code, selected_dress_id;
END;
$$;

REVOKE ALL
ON FUNCTION public.create_purchase_transaction(bigint,date,varchar,varchar,bigint,varchar,bigint,varchar,varchar,numeric,numeric,integer)
FROM PUBLIC;

GRANT EXECUTE
ON FUNCTION public.create_purchase_transaction(bigint,date,varchar,varchar,bigint,varchar,bigint,varchar,varchar,numeric,numeric,integer)
TO authenticated;

NOTIFY pgrst, 'reload schema';