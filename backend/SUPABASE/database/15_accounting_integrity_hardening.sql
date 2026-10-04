-- Accounting hardening: capital reversal and deferred journal balance validation.
-- Run after 14_purchase_inventory_integration.sql.

CREATE OR REPLACE FUNCTION cancel_capital_contribution(
  p_capital_id bigint,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  capital_row capital_contributions%ROWTYPE;
  cash_account_code varchar;
BEGIN
  SELECT *
  INTO capital_row
  FROM capital_contributions
  WHERE id = p_capital_id
  FOR UPDATE;

  IF capital_row.id IS NULL THEN
    RAISE EXCEPTION 'Setoran modal tidak ditemukan';
  END IF;

  IF capital_row.status <> 'Posted' THEN
    RAISE EXCEPTION 'Setoran modal sudah dibatalkan';
  END IF;

  IF nullif(trim(p_reason),'') IS NULL THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi';
  END IF;

  SELECT account_code
  INTO cash_account_code
  FROM accounts
  WHERE id = capital_row.cash_account_id;

  IF cash_account_code IS NULL THEN
    RAISE EXCEPTION 'Akun kas/bank setoran modal tidak ditemukan';
  END IF;

  PERFORM post_two_line_journal(
    next_business_code('journal'),
    current_date,
    'capital_reversal',
    capital_row.id,
    'Pembalikan setoran modal ' || capital_row.capital_code,
    '301',
    cash_account_code,
    capital_row.amount
  );

  UPDATE capital_contributions
  SET
    status = 'Cancelled',
    description = concat_ws(' | ',description,'Dibatalkan: ' || trim(p_reason))
  WHERE id = p_capital_id;
END;
$$;

GRANT EXECUTE ON FUNCTION cancel_capital_contribution(bigint,text) TO authenticated;

CREATE OR REPLACE FUNCTION enforce_journal_balance()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF COALESCE(NEW.journal_id, OLD.journal_id) IS NOT NULL
    AND NOT journal_is_balanced(COALESCE(NEW.journal_id, OLD.journal_id))
  THEN
    RAISE EXCEPTION 'Jurnal % tidak balance: total debit harus sama dengan total kredit', COALESCE(NEW.journal_id, OLD.journal_id);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS journal_details_balance_check ON journal_details;

CREATE CONSTRAINT TRIGGER journal_details_balance_check
AFTER INSERT OR UPDATE OR DELETE ON journal_details
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION enforce_journal_balance();

NOTIFY pgrst, 'reload schema';