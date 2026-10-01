-- Auth bootstrap and RLS repair. Run after 10_settings_security_inventory.sql.
-- app_users is the existing profile table; no password is stored here.

CREATE OR REPLACE FUNCTION ensure_app_user_profile()
RETURNS TABLE(
  profile_id uuid,
  profile_role text,
  profile_active boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  auth_record record;
BEGIN
  SELECT
    id,
    email,
    raw_user_meta_data
  INTO auth_record
  FROM auth.users
  WHERE id = auth.uid();

  IF auth_record.id IS NULL THEN
    RAISE EXCEPTION 'Authenticated user not found';
  END IF;

  INSERT INTO app_users(
    auth_user_id,
    full_name,
    email,
    role,
    is_active
  )
  VALUES(
    auth_record.id,
    coalesce(auth_record.raw_user_meta_data->>'full_name',split_part(auth_record.email,'@',1)),
    auth_record.email,
    'staff',
    true
  )
  ON CONFLICT (auth_user_id)
  DO UPDATE SET
    email=excluded.email,
    updated_at=now()
  RETURNING
    id,
    lower(role),
    is_active
  INTO
    profile_id,
    profile_role,
    profile_active;

  RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION ensure_app_user_profile() TO authenticated;

DROP POLICY IF EXISTS app_users_self_read ON app_users;

CREATE POLICY app_users_self_read
ON app_users
FOR SELECT
TO authenticated
USING (auth_user_id = auth.uid() OR current_app_role() = 'admin');

DROP POLICY IF EXISTS accounts_authenticated_insert ON accounts;

CREATE POLICY accounts_authenticated_insert
ON accounts
FOR INSERT
TO authenticated
WITH CHECK (current_app_role() IN ('admin','accounting'));

DROP POLICY IF EXISTS accounts_authenticated_update ON accounts;

CREATE POLICY accounts_authenticated_update
ON accounts
FOR UPDATE
TO authenticated
USING (current_app_role() IN ('admin','accounting'))
WITH CHECK (current_app_role() IN ('admin','accounting'));

DROP POLICY IF EXISTS categories_authenticated_insert ON dress_categories;

CREATE POLICY categories_authenticated_insert
ON dress_categories
FOR INSERT
TO authenticated
WITH CHECK (current_app_role() IN ('admin','staff'));

DROP POLICY IF EXISTS expense_categories_authenticated_insert ON expense_categories;

CREATE POLICY expense_categories_authenticated_insert
ON expense_categories
FOR INSERT
TO authenticated
WITH CHECK (current_app_role() IN ('admin','staff','accounting'));

REVOKE ALL ON SEQUENCE
  customer_number_seq,
  supplier_number_seq,
  dress_number_seq,
  rental_number_seq,
  payment_number_seq,
  purchase_number_seq,
  expense_number_seq,
  return_number_seq,
  penalty_number_seq,
  journal_number_seq,
  movement_number_seq
FROM authenticated;