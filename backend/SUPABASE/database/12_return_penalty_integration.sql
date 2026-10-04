-- Atomic return, late-fee, damage, and one-return enforcement.
-- Run after 11_auth_rls_hotfix.sql.

ALTER TABLE returns
  ADD COLUMN IF NOT EXISTS late_rate numeric(15,2) NOT NULL DEFAULT 0 CHECK (late_rate >= 0);

ALTER TABLE returns
  ADD COLUMN IF NOT EXISTS late_penalty numeric(15,2) NOT NULL DEFAULT 0 CHECK (late_penalty >= 0);

ALTER TABLE returns
  ADD COLUMN IF NOT EXISTS damage_amount numeric(15,2) NOT NULL DEFAULT 0 CHECK (damage_amount >= 0);

ALTER TABLE returns
  ADD COLUMN IF NOT EXISTS total_penalty numeric(15,2) NOT NULL DEFAULT 0 CHECK (total_penalty >= 0);

ALTER TABLE returns
  ADD COLUMN IF NOT EXISTS penalty_payment_status varchar(30) NOT NULL DEFAULT 'Unpaid';

ALTER TABLE returns
  DROP CONSTRAINT IF EXISTS returns_condition_check;

ALTER TABLE returns
  ADD CONSTRAINT returns_condition_check
  CHECK (condition IN ('Baik','Kotor','Rusak Ringan','Rusak Berat','Hilang'));

ALTER TABLE returns
  DROP CONSTRAINT IF EXISTS returns_penalty_payment_status_check;

ALTER TABLE returns
  ADD CONSTRAINT returns_penalty_payment_status_check
  CHECK (penalty_payment_status IN ('Unpaid','Partially Paid','Paid'));

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM returns
    GROUP BY rental_id
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'Duplicate return ditemukan. Bersihkan data returns per rental_id sebelum membuat unique index.';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS returns_one_per_rental_idx
  ON returns(rental_id);

CREATE OR REPLACE FUNCTION apply_return_dress_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  target_status varchar(30);
BEGIN
  target_status := CASE NEW.condition
    WHEN 'Baik' THEN 'Available'
    WHEN 'Kotor' THEN 'Laundry'
    WHEN 'Rusak Ringan' THEN 'Repair'
    WHEN 'Rusak Berat' THEN 'Not Available'
    WHEN 'Hilang' THEN 'Not Available'
    ELSE 'Available'
  END;

  UPDATE dresses
  SET status = target_status
  WHERE id IN (
    SELECT dress_id
    FROM rental_details
    WHERE rental_id = NEW.rental_id
  );

  RETURN NEW;
END;
$$;

ALTER FUNCTION trg_complete_rental() SECURITY DEFINER;
ALTER FUNCTION trg_complete_rental() SET search_path = public;

CREATE OR REPLACE FUNCTION prevent_duplicate_return()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rental_row rentals%ROWTYPE;
BEGIN
  SELECT *
  INTO rental_row
  FROM rentals
  WHERE id = NEW.rental_id
  FOR UPDATE;

  IF rental_row.id IS NULL THEN
    RAISE EXCEPTION 'Rental tidak ditemukan';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM returns
    WHERE rental_id = NEW.rental_id
  ) THEN
    RAISE EXCEPTION 'Rental sudah memiliki pengembalian';
  END IF;

  IF coalesce(rental_row.rental_status, rental_row.status) IN ('Returned','Completed','Cancelled')
    OR rental_row.status IN ('Completed','Cancelled')
  THEN
    RAISE EXCEPTION 'Rental berstatus % tidak dapat dikembalikan', coalesce(rental_row.rental_status, rental_row.status);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_duplicate_return ON returns;

CREATE TRIGGER prevent_duplicate_return
BEFORE INSERT ON returns
FOR EACH ROW
EXECUTE FUNCTION prevent_duplicate_return();

CREATE OR REPLACE FUNCTION process_return_transaction(
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
  rental_row rentals%ROWTYPE;
  new_return returns%ROWTYPE;
  new_penalty penalties%ROWTYPE;
  new_payment penalty_payments%ROWTYPE;
  new_penalty_id bigint;
  new_payment_id bigint;
  late_days_value integer;
  late_amount numeric;
  total_amount numeric;
  damage_value numeric := greatest(coalesce(p_damage_amount,0),0);
  payment_value numeric := greatest(coalesce(p_payment_amount,0),0);
BEGIN
  SELECT *
  INTO rental_row
  FROM rentals
  WHERE id = p_rental_id
  FOR UPDATE;

  IF rental_row.id IS NULL THEN
    RAISE EXCEPTION 'Rental tidak ditemukan';
  END IF;

  IF p_return_date IS NULL THEN
    RAISE EXCEPTION 'Tanggal pengembalian wajib diisi';
  END IF;

  IF p_condition NOT IN ('Baik','Kotor','Rusak Ringan','Rusak Berat','Hilang') THEN
    RAISE EXCEPTION 'Kondisi pengembalian tidak valid';
  END IF;

  IF p_late_rate < 0 OR damage_value < 0 OR payment_value < 0 THEN
    RAISE EXCEPTION 'Nominal denda tidak boleh negatif';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM returns
    WHERE rental_id = p_rental_id
  ) THEN
    RAISE EXCEPTION 'Rental sudah memiliki pengembalian';
  END IF;

  IF coalesce(rental_row.rental_status, rental_row.status) IN ('Returned','Completed','Cancelled')
    OR rental_row.status IN ('Completed','Cancelled')
  THEN
    RAISE EXCEPTION 'Rental berstatus % tidak dapat dikembalikan', coalesce(rental_row.rental_status, rental_row.status);
  END IF;

  late_days_value := greatest(0, p_return_date - rental_row.return_due_date);
  late_amount := late_days_value * coalesce(p_late_rate,0);
  total_amount := late_amount + damage_value;

  IF payment_value > total_amount THEN
    RAISE EXCEPTION 'Pembayaran denda melebihi total denda';
  END IF;

  INSERT INTO returns(
    rental_id,
    return_date,
    condition,
    late_days,
    notes,
    late_rate,
    late_penalty,
    damage_amount,
    total_penalty,
    penalty_payment_status
  )
  VALUES(
    p_rental_id,
    p_return_date,
    p_condition,
    late_days_value,
    p_notes,
    coalesce(p_late_rate,0),
    late_amount,
    damage_value,
    total_amount,
    CASE
      WHEN total_amount = 0 THEN 'Paid'
      WHEN payment_value = 0 THEN 'Unpaid'
      WHEN payment_value < total_amount THEN 'Partially Paid'
      ELSE 'Paid'
    END
  )
  RETURNING * INTO new_return;

  INSERT INTO dress_movements(
    dress_id,
    movement_type,
    reference_id,
    reference_code,
    status_before,
    status_after,
    description
  )
  SELECT
    rd.dress_id,
    'RETURN',
    new_return.id,
    new_return.return_code,
    'Rented',
    CASE p_condition
      WHEN 'Baik' THEN 'Available'
      WHEN 'Kotor' THEN 'Laundry'
      WHEN 'Rusak Ringan' THEN 'Repair'
      ELSE 'Not Available'
    END,
    'Dress kembali dari pengembalian'
  FROM rental_details rd
  WHERE rd.rental_id = p_rental_id;

  IF total_amount > 0 THEN
    INSERT INTO penalties(
      return_id,
      penalty_type,
      amount,
      description
    )
    VALUES(
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
      INSERT INTO penalty_payments(
        penalty_id,
        payment_date,
        amount,
        payment_method,
        description
      )
      VALUES(
        new_penalty.id,
        p_return_date,
        payment_value,
        p_payment_method,
        'Pembayaran denda saat pengembalian'
      )
      RETURNING * INTO new_payment;

      new_payment_id := new_payment.id;
    END IF;
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

GRANT EXECUTE ON FUNCTION process_return_transaction(bigint,date,varchar,text,numeric,numeric,numeric,varchar) TO authenticated;

ALTER FUNCTION post_two_line_journal(varchar,date,varchar,bigint,varchar,varchar,varchar,numeric) SECURITY DEFINER;
ALTER FUNCTION post_two_line_journal(varchar,date,varchar,bigint,varchar,varchar,varchar,numeric) SET search_path = public;

ALTER FUNCTION trg_rental_journal() SECURITY DEFINER;
ALTER FUNCTION trg_rental_journal() SET search_path = public;

ALTER FUNCTION trg_purchase_journal() SECURITY DEFINER;
ALTER FUNCTION trg_purchase_journal() SET search_path = public;

ALTER FUNCTION trg_customer_payment_journal() SECURITY DEFINER;
ALTER FUNCTION trg_customer_payment_journal() SET search_path = public;

ALTER FUNCTION trg_purchase_payment_journal() SECURITY DEFINER;
ALTER FUNCTION trg_purchase_payment_journal() SET search_path = public;

ALTER FUNCTION trg_expense_journal() SECURITY DEFINER;
ALTER FUNCTION trg_expense_journal() SET search_path = public;

ALTER FUNCTION trg_expense_payment_journal() SECURITY DEFINER;
ALTER FUNCTION trg_expense_payment_journal() SET search_path = public;

ALTER FUNCTION trg_penalty_journal() SECURITY DEFINER;
ALTER FUNCTION trg_penalty_journal() SET search_path = public;

ALTER FUNCTION trg_penalty_payment_journal() SECURITY DEFINER;
ALTER FUNCTION trg_penalty_payment_journal() SET search_path = public;

NOTIFY pgrst, 'reload schema';