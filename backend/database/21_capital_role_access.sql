-- Allow the authenticated operational role to post owner capital through the
-- guarded RPC. The database still validates session, account, amount, and journal trigger.
-- Run after 20_capital_posting_rpc.sql.

CREATE OR REPLACE FUNCTION create_capital_contribution(
  p_contribution_date date,
  p_owner_name varchar,
  p_contribution_type varchar,
  p_cash_account_id bigint,
  p_amount numeric,
  p_description text DEFAULT NULL
)
RETURNS capital_contributions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_capital capital_contributions%ROWTYPE;
  account_code_value varchar;
BEGIN
  IF current_app_role() NOT IN ('admin','accounting','owner','staff') THEN
    RAISE EXCEPTION 'Role Anda tidak memiliki akses posting modal';
  END IF;

  IF p_contribution_date IS NULL OR nullif(trim(p_owner_name),'') IS NULL THEN
    RAISE EXCEPTION 'Tanggal dan pemilik wajib diisi';
  END IF;

  IF p_contribution_type NOT IN ('Cash','Bank Transfer') THEN
    RAISE EXCEPTION 'Jenis setoran tidak valid';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Jumlah modal harus lebih besar dari nol';
  END IF;

  SELECT account_code
  INTO account_code_value
  FROM accounts
  WHERE id = p_cash_account_id
    AND account_type = 'Asset';

  IF account_code_value IS NULL OR account_code_value NOT IN ('101','1120') THEN
    RAISE EXCEPTION 'Akun penerimaan harus Kas atau Bank';
  END IF;

  INSERT INTO capital_contributions(
    contribution_date,
    owner_name,
    contribution_type,
    cash_account_id,
    amount,
    description,
    status,
    created_by
  )
  VALUES(
    p_contribution_date,
    trim(p_owner_name),
    p_contribution_type,
    p_cash_account_id,
    p_amount,
    p_description,
    'Posted',
    auth.uid()
  )
  RETURNING * INTO new_capital;

  RETURN new_capital;
END;
$$;

GRANT EXECUTE ON FUNCTION create_capital_contribution(date,varchar,varchar,bigint,numeric,text) TO authenticated;

DROP POLICY IF EXISTS capital_insert ON capital_contributions;

CREATE POLICY capital_insert
ON capital_contributions
FOR INSERT
TO authenticated
WITH CHECK (
  current_app_role() IN ('admin','accounting','owner','staff')
  AND created_by = auth.uid()
);

NOTIFY pgrst, 'reload schema';