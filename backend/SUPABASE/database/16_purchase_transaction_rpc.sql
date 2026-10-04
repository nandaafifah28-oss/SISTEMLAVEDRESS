-- Atomic purchase transaction: dress master, purchase, detail, movement, and journal.
-- Run after 15_accounting_integrity_hardening.sql.

CREATE OR REPLACE FUNCTION create_purchase_transaction(
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
  purchase_row purchases%ROWTYPE;
  selected_dress_id bigint := p_dress_id;
  total_value numeric;
BEGIN
  IF p_supplier_id IS NULL OR p_purchase_date IS NULL THEN
    RAISE EXCEPTION 'Supplier dan tanggal pembelian wajib diisi';
  END IF;

  IF p_payment_status NOT IN ('Paid','Unpaid') THEN
    RAISE EXCEPTION 'Status pembayaran purchase tidak valid';
  END IF;

  IF p_payment_method NOT IN ('Cash','Transfer','E-Wallet') THEN
    RAISE EXCEPTION 'Metode pembayaran purchase tidak valid';
  END IF;

  IF p_purchase_price <= 0 OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Harga beli dan quantity harus lebih besar dari nol';
  END IF;

  IF selected_dress_id IS NULL THEN
    IF nullif(trim(p_dress_name),'') IS NULL
      OR p_category_id IS NULL
      OR nullif(trim(p_size),'') IS NULL
    THEN
      RAISE EXCEPTION 'Data dress baru belum lengkap';
    END IF;

    INSERT INTO dresses(
      name,
      category_id,
      size,
      color,
      purchase_price,
      rental_price,
      supplier_id,
      condition,
      status,
      is_active
    )
    VALUES(
      trim(p_dress_name),
      p_category_id,
      trim(p_size),
      nullif(trim(p_color),''),
      p_purchase_price,
      greatest(p_rental_price,0),
      p_supplier_id,
      'Good',
      'Available',
      true
    )
    RETURNING id INTO selected_dress_id;
  ELSE
    PERFORM 1
    FROM dresses
    WHERE id = selected_dress_id
    FOR UPDATE;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Dress tidak ditemukan';
    END IF;

    UPDATE dresses
    SET
      purchase_price=p_purchase_price,
      rental_price=greatest(p_rental_price,0),
      supplier_id=p_supplier_id,
      status='Available',
      condition='Good',
      is_active=true
    WHERE id=selected_dress_id;
  END IF;

  total_value := p_purchase_price * p_quantity;

  INSERT INTO purchases(
    supplier_id,
    purchase_date,
    total_amount,
    payment_status,
    payment_method
  )
  VALUES(
    p_supplier_id,
    p_purchase_date,
    total_value,
    p_payment_status,
    p_payment_method
  )
  RETURNING * INTO purchase_row;

  INSERT INTO purchase_details(
    purchase_id,
    dress_id,
    quantity,
    purchase_price,
    subtotal
  )
  VALUES(
    purchase_row.id,
    selected_dress_id,
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

GRANT EXECUTE ON FUNCTION create_purchase_transaction(bigint,date,varchar,varchar,bigint,varchar,bigint,varchar,varchar,numeric,numeric,integer) TO authenticated;

NOTIFY pgrst, 'reload schema';