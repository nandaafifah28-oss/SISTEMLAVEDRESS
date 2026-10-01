-- Purchase detail to inventory movement integration.
-- Run after 13_capital_contribution.sql.

CREATE OR REPLACE FUNCTION record_purchase_inventory_movement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  purchase_code_value varchar;
  previous_status varchar;
BEGIN
  SELECT purchase_code
  INTO purchase_code_value
  FROM purchases
  WHERE id = NEW.purchase_id;

  IF purchase_code_value IS NULL THEN
    RAISE EXCEPTION 'Purchase tidak ditemukan';
  END IF;

  SELECT status
  INTO previous_status
  FROM dresses
  WHERE id = NEW.dress_id
  FOR UPDATE;

  UPDATE dresses
  SET
    status = 'Available',
    condition = 'Good'
  WHERE id = NEW.dress_id;

  INSERT INTO dress_movements(
    dress_id,
    movement_type,
    reference_id,
    reference_code,
    status_before,
    status_after,
    description
  )
  VALUES(
    NEW.dress_id,
    'PURCHASE_IN',
    NEW.purchase_id,
    purchase_code_value,
    previous_status,
    'Available',
    'Dress masuk melalui pembelian'
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_purchase_detail_inventory ON purchase_details;

CREATE TRIGGER after_purchase_detail_inventory
AFTER INSERT ON purchase_details
FOR EACH ROW
EXECUTE FUNCTION record_purchase_inventory_movement();

ALTER FUNCTION record_purchase_inventory_movement() SECURITY DEFINER;
ALTER FUNCTION record_purchase_inventory_movement() SET search_path = public;

NOTIFY pgrst, 'reload schema';