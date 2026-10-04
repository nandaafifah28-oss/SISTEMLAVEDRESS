-- Safe migration for integrated rental, payment, return, and dress status flow.
-- This keeps the existing schema intact and only adds compatibility fields/checks.

-- Remove the previously deployed polymorphic trigger before any migration work.
DROP TRIGGER IF EXISTS assign_customer_code ON customers;
DROP TRIGGER IF EXISTS assign_supplier_code ON suppliers;
DROP TRIGGER IF EXISTS assign_dress_code ON dresses;
DROP TRIGGER IF EXISTS assign_rental_code ON rentals;
DROP TRIGGER IF EXISTS assign_payment_code ON payments;
DROP TRIGGER IF EXISTS assign_purchase_code ON purchases;
DROP TRIGGER IF EXISTS assign_expense_code ON expenses;
DROP TRIGGER IF EXISTS assign_return_code ON returns;
DROP TRIGGER IF EXISTS assign_penalty_code ON penalties;
DROP TRIGGER IF EXISTS assign_movement_code ON dress_movements;
DROP TRIGGER IF EXISTS assign_journal_code ON journal_entries;
DROP FUNCTION IF EXISTS assign_transaction_codes() CASCADE;

DO $$
DECLARE
  old_trigger record;
BEGIN
  FOR old_trigger IN
    SELECT
      n.nspname AS event_object_schema,
      c.relname AS event_object_table,
      t.tgname AS trigger_name
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    WHERE p.proname = 'assign_transaction_codes'
      AND NOT t.tgisinternal
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS %I ON %I.%I',
      old_trigger.trigger_name,
      old_trigger.event_object_schema,
      old_trigger.event_object_table
    );
  END LOOP;
END;
$$;

DROP FUNCTION IF EXISTS public.assign_transaction_codes() CASCADE;

ALTER TABLE suppliers
  ADD COLUMN IF NOT EXISTS supplier_code varchar(20);

CREATE UNIQUE INDEX IF NOT EXISTS suppliers_supplier_code_key
  ON suppliers(supplier_code);

ALTER TABLE rentals
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE rentals
  ADD COLUMN IF NOT EXISTS total_rental numeric(15,2);

ALTER TABLE rentals
  ADD COLUMN IF NOT EXISTS rental_status varchar(30) DEFAULT 'Booked';

ALTER TABLE rentals
  ADD COLUMN IF NOT EXISTS payment_status varchar(30) DEFAULT 'Unpaid';

ALTER TABLE rentals
  ADD COLUMN IF NOT EXISTS cancellation_reason text;

ALTER TABLE rentals
  ADD COLUMN IF NOT EXISTS cancelled_at timestamptz;

ALTER TABLE rental_details
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS payment_type varchar(30) DEFAULT 'PELUNASAN';

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS notes text;

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS payment_reference varchar(100);

ALTER TABLE returns
  ADD COLUMN IF NOT EXISTS return_code varchar(30);

ALTER TABLE penalties
  ADD COLUMN IF NOT EXISTS penalty_code varchar(30);

ALTER TABLE dress_movements
  ADD COLUMN IF NOT EXISTS movement_code varchar(30);

ALTER TABLE returns
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE penalties
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

ALTER TABLE dresses
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

CREATE SEQUENCE IF NOT EXISTS customer_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS supplier_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS dress_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS rental_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS payment_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS purchase_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS expense_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS return_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS penalty_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS journal_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS movement_number_seq START WITH 1;

DO $$
BEGIN
  PERFORM setval(
    'customer_number_seq',
    coalesce(
      (
        SELECT max(substring(customer_code from 5)::bigint)
        FROM customers
        WHERE customer_code ~ '^CUS-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );

  PERFORM setval(
    'supplier_number_seq',
    coalesce(
      (
        SELECT max(substring(supplier_code from 5)::bigint)
        FROM suppliers
        WHERE supplier_code ~ '^SUP-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );

  PERFORM setval(
    'dress_number_seq',
    coalesce(
      (
        SELECT max(substring(dress_code from 5)::bigint)
        FROM dresses
        WHERE dress_code ~ '^DRS-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );

  PERFORM setval(
    'rental_number_seq',
    coalesce(
      (
        SELECT max(substring(rental_code from 6)::bigint)
        FROM rentals
        WHERE rental_code ~ '^RENT-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );

  PERFORM setval(
    'payment_number_seq',
    coalesce(
      (
        SELECT max(substring(payment_code from 5)::bigint)
        FROM payments
        WHERE payment_code ~ '^PAY-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );

  PERFORM setval(
    'purchase_number_seq',
    coalesce(
      (
        SELECT max(substring(purchase_code from 5)::bigint)
        FROM purchases
        WHERE purchase_code ~ '^PUR-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );

  PERFORM setval(
    'expense_number_seq',
    coalesce(
      (
        SELECT max(substring(expense_code from 5)::bigint)
        FROM expenses
        WHERE expense_code ~ '^EXP-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );

  PERFORM setval(
    'return_number_seq',
    coalesce(
      (
        SELECT max(substring(return_code from 5)::bigint)
        FROM returns
        WHERE return_code ~ '^RET-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );

  PERFORM setval(
    'penalty_number_seq',
    coalesce(
      (
        SELECT max(substring(penalty_code from 5)::bigint)
        FROM penalties
        WHERE penalty_code ~ '^PEN-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );

  PERFORM setval(
    'journal_number_seq',
    coalesce(
      (
        SELECT max(substring(journal_code from 5)::bigint)
        FROM journal_entries
        WHERE journal_code ~ '^JRN-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );

  PERFORM setval(
    'movement_number_seq',
    coalesce(
      (
        SELECT max(substring(movement_code from 5)::bigint)
        FROM dress_movements
        WHERE movement_code ~ '^MOV-[0-9]+$'
      ),
      0
    ) + 1,
    false
  );
END $$;

CREATE OR REPLACE FUNCTION next_business_code(p_type text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF lower(p_type) = 'customer' THEN
    RETURN 'CUS-' || lpad(nextval('customer_number_seq')::text, 4, '0');
  END IF;

  IF lower(p_type) = 'supplier' THEN
    RETURN 'SUP-' || lpad(nextval('supplier_number_seq')::text, 4, '0');
  END IF;

  IF lower(p_type) = 'dress' THEN
    RETURN 'DRS-' || lpad(nextval('dress_number_seq')::text, 4, '0');
  END IF;

  IF lower(p_type) = 'rental' THEN
    RETURN 'RENT-' || lpad(nextval('rental_number_seq')::text, 4, '0');
  END IF;

  IF lower(p_type) = 'payment' THEN
    RETURN 'PAY-' || lpad(nextval('payment_number_seq')::text, 4, '0');
  END IF;

  IF lower(p_type) = 'purchase' THEN
    RETURN 'PUR-' || lpad(nextval('purchase_number_seq')::text, 4, '0');
  END IF;

  IF lower(p_type) = 'expense' THEN
    RETURN 'EXP-' || lpad(nextval('expense_number_seq')::text, 4, '0');
  END IF;

  IF lower(p_type) = 'return' THEN
    RETURN 'RET-' || lpad(nextval('return_number_seq')::text, 4, '0');
  END IF;

  IF lower(p_type) = 'penalty' THEN
    RETURN 'PEN-' || lpad(nextval('penalty_number_seq')::text, 4, '0');
  END IF;

  IF lower(p_type) = 'journal' THEN
    RETURN 'JRN-' || lpad(nextval('journal_number_seq')::text, 4, '0');
  END IF;

  IF lower(p_type) = 'movement' THEN
    RETURN 'MOV-' || lpad(nextval('movement_number_seq')::text, 4, '0');
  END IF;

  RAISE EXCEPTION 'Unknown business code type: %', p_type;
END;
$$;

CREATE OR REPLACE FUNCTION assign_customer_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.customer_code, '') IS NULL THEN
    NEW.customer_code := next_business_code('customer');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_supplier_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.supplier_code, '') IS NULL THEN
    NEW.supplier_code := next_business_code('supplier');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_dress_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.dress_code, '') IS NULL THEN
    NEW.dress_code := next_business_code('dress');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_rental_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.rental_code, '') IS NULL THEN
    NEW.rental_code := next_business_code('rental');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_payment_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.payment_code, '') IS NULL THEN
    NEW.payment_code := next_business_code('payment');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_purchase_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.purchase_code, '') IS NULL THEN
    NEW.purchase_code := next_business_code('purchase');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_expense_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.expense_code, '') IS NULL THEN
    NEW.expense_code := next_business_code('expense');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_return_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.return_code, '') IS NULL THEN
    NEW.return_code := next_business_code('return');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_penalty_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.penalty_code, '') IS NULL THEN
    NEW.penalty_code := next_business_code('penalty');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_movement_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.movement_code, '') IS NULL THEN
    NEW.movement_code := next_business_code('movement');
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_journal_code()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.journal_code, '') IS NULL THEN
    NEW.journal_code := next_business_code('journal');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assign_customer_code ON customers;

CREATE TRIGGER assign_customer_code
BEFORE INSERT ON customers
FOR EACH ROW
EXECUTE FUNCTION assign_customer_code();

DROP TRIGGER IF EXISTS assign_supplier_code ON suppliers;

CREATE TRIGGER assign_supplier_code
BEFORE INSERT ON suppliers
FOR EACH ROW
EXECUTE FUNCTION assign_supplier_code();

DROP TRIGGER IF EXISTS assign_dress_code ON dresses;

CREATE TRIGGER assign_dress_code
BEFORE INSERT ON dresses
FOR EACH ROW
EXECUTE FUNCTION assign_dress_code();

DROP TRIGGER IF EXISTS assign_rental_code ON rentals;

CREATE TRIGGER assign_rental_code
BEFORE INSERT ON rentals
FOR EACH ROW
EXECUTE FUNCTION assign_rental_code();

DROP TRIGGER IF EXISTS assign_payment_code ON payments;

CREATE TRIGGER assign_payment_code
BEFORE INSERT ON payments
FOR EACH ROW
EXECUTE FUNCTION assign_payment_code();

DROP TRIGGER IF EXISTS assign_purchase_code ON purchases;

CREATE TRIGGER assign_purchase_code
BEFORE INSERT ON purchases
FOR EACH ROW
EXECUTE FUNCTION assign_purchase_code();

DROP TRIGGER IF EXISTS assign_expense_code ON expenses;

CREATE TRIGGER assign_expense_code
BEFORE INSERT ON expenses
FOR EACH ROW
EXECUTE FUNCTION assign_expense_code();

DROP TRIGGER IF EXISTS assign_return_code ON returns;

CREATE TRIGGER assign_return_code
BEFORE INSERT ON returns
FOR EACH ROW
EXECUTE FUNCTION assign_return_code();

DROP TRIGGER IF EXISTS assign_penalty_code ON penalties;

CREATE TRIGGER assign_penalty_code
BEFORE INSERT ON penalties
FOR EACH ROW
EXECUTE FUNCTION assign_penalty_code();

DROP TRIGGER IF EXISTS assign_movement_code ON dress_movements;

CREATE TRIGGER assign_movement_code
BEFORE INSERT ON dress_movements
FOR EACH ROW
EXECUTE FUNCTION assign_movement_code();

DROP TRIGGER IF EXISTS assign_journal_code ON journal_entries;

CREATE TRIGGER assign_journal_code
BEFORE INSERT ON journal_entries
FOR EACH ROW
EXECUTE FUNCTION assign_journal_code();

DROP FUNCTION IF EXISTS assign_transaction_codes() CASCADE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'rentals_status_check'
  ) THEN
    ALTER TABLE rentals
    ADD CONSTRAINT rentals_status_check
      CHECK (status IN ('Booked','Ongoing','Completed','Cancelled','Paid','Partially Paid'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'dresses_status_check'
  ) THEN
    ALTER TABLE dresses
    ADD CONSTRAINT dresses_status_check
      CHECK (status IN ('Available','Rented','Laundry','Repair','Not Available'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'returns_condition_check'
  ) THEN
    ALTER TABLE returns
    ADD CONSTRAINT returns_condition_check
      CHECK (condition IN ('Baik','Kotor','Rusak Ringan','Rusak Berat'));
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'payments_payment_method_check'
  ) THEN
    ALTER TABLE payments
    ADD CONSTRAINT payments_payment_method_check
      CHECK (payment_method IN ('Cash','Transfer','E-Wallet'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_rentals_customer
  ON rentals(customer_id);

CREATE INDEX IF NOT EXISTS idx_rentals_period
  ON rentals(rental_date, return_due_date);

CREATE INDEX IF NOT EXISTS idx_payments_rental
  ON payments(rental_id);

CREATE INDEX IF NOT EXISTS idx_returns_rental
  ON returns(rental_id);

CREATE INDEX IF NOT EXISTS idx_penalties_return
  ON penalties(return_id);

UPDATE rentals
SET total_rental = total_amount
WHERE total_rental IS NULL;

UPDATE rentals r
SET payment_status = CASE
  WHEN coalesce(p.paid_amount, 0) <= 0 THEN 'Unpaid'
  WHEN coalesce(p.paid_amount, 0) < coalesce(r.total_rental, r.total_amount, 0) THEN 'Partially Paid'
  ELSE 'Paid'
END
FROM (
  SELECT
    rental_id,
    sum(
      CASE
        WHEN payment_type = 'REFUND' THEN -amount
        ELSE amount
      END
    ) AS paid_amount
  FROM payments
  GROUP BY rental_id
) p
WHERE r.id = p.rental_id
  AND coalesce(r.rental_status, r.status) <> 'Cancelled';

UPDATE rentals
SET rental_status = CASE
  WHEN status = 'Cancelled' THEN 'Cancelled'
  WHEN status = 'Completed' THEN 'Completed'
  WHEN status = 'Ongoing' THEN 'Ongoing'
  ELSE 'Booked'
END
WHERE rental_status IS NULL;

ALTER TABLE rentals
  ALTER COLUMN total_rental SET DEFAULT 0;

ALTER TABLE payments
  ALTER COLUMN payment_type SET DEFAULT 'PELUNASAN';

ALTER TABLE payments
  DROP CONSTRAINT IF EXISTS payments_payment_method_check;

ALTER TABLE payments
  ADD CONSTRAINT payments_payment_method_check
  CHECK (payment_method IN ('Cash','Transfer','Transfer Bank','E-Wallet','QRIS','Lainnya'));

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'payments_type_check'
  ) THEN
    ALTER TABLE payments
    ADD CONSTRAINT payments_type_check
      CHECK (payment_type IN ('DP','PELUNASAN','DENDA','REFUND'));
  END IF;
END $$;

INSERT INTO accounts(account_code, account_name, account_type)
VALUES ('403','Pendapatan Pembatalan','Revenue')
ON CONFLICT (account_code) DO NOTHING;

CREATE TABLE IF NOT EXISTS purchase_payments(
  id bigint generated by default as identity primary key,
  purchase_id bigint not null references purchases(id) on delete cascade,
  payment_date date not null,
  amount numeric(15,2) not null check(amount > 0),
  payment_method varchar(30) not null check(payment_method in ('Cash','Transfer','E-Wallet')),
  description text,
  created_at timestamptz default now()
);

CREATE INDEX IF NOT EXISTS idx_purchase_payments_purchase
  ON purchase_payments(purchase_id);

ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS payment_status varchar(30) NOT NULL DEFAULT 'Paid';

ALTER TABLE expenses
  ADD COLUMN IF NOT EXISTS recipient varchar(150);

ALTER TABLE purchases
  ADD COLUMN IF NOT EXISTS payment_method varchar(30) DEFAULT 'Cash';

CREATE TABLE IF NOT EXISTS expense_payments(
  id bigint generated by default as identity primary key,
  expense_id bigint not null references expenses(id) on delete cascade,
  payment_date date not null,
  amount numeric(15,2) not null check(amount > 0),
  payment_method varchar(30) not null check(payment_method in ('Cash','Transfer','E-Wallet')),
  description text,
  created_at timestamptz default now()
);

CREATE INDEX IF NOT EXISTS idx_expense_payments_expense
  ON expense_payments(expense_id);

CREATE TABLE IF NOT EXISTS penalty_payments(
  id bigint generated by default as identity primary key,
  penalty_id bigint not null references penalties(id) on delete cascade,
  payment_date date not null,
  amount numeric(15,2) not null check(amount > 0),
  payment_method varchar(30) not null check(payment_method in ('Cash','Transfer','E-Wallet')),
  description text,
  created_at timestamptz default now()
);

CREATE INDEX IF NOT EXISTS idx_penalty_payments_penalty
  ON penalty_payments(penalty_id);

INSERT INTO expense_categories(category_name)
VALUES ('Air')
ON CONFLICT (category_name) DO NOTHING;

CREATE OR REPLACE FUNCTION post_two_line_journal(
  p_journal_code varchar,
  p_journal_date date,
  p_reference_type varchar,
  p_reference_id bigint,
  p_description varchar,
  p_debit_code varchar,
  p_credit_code varchar,
  p_amount numeric
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  journal_id bigint;
  debit_account_id bigint;
  credit_account_id bigint;
BEGIN
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM journal_entries
    WHERE journal_code = p_journal_code
  ) THEN
    RETURN;
  END IF;

  SELECT id
  INTO debit_account_id
  FROM accounts
  WHERE account_code = p_debit_code
  LIMIT 1;

  SELECT id
  INTO credit_account_id
  FROM accounts
  WHERE account_code = p_credit_code
  LIMIT 1;

  IF debit_account_id IS NULL OR credit_account_id IS NULL THEN
    RAISE EXCEPTION 'Account % or % is not configured', p_debit_code, p_credit_code;
  END IF;

  INSERT INTO journal_entries(
    journal_code,
    journal_date,
    reference_type,
    reference_id,
    description
  )
  VALUES(
    p_journal_code,
    p_journal_date,
    p_reference_type,
    p_reference_id,
    p_description
  )
  RETURNING id INTO journal_id;

  INSERT INTO journal_details(
    journal_id,
    account_id,
    debit,
    credit
  )
  VALUES
    (journal_id,debit_account_id,p_amount,0),
    (journal_id,credit_account_id,0,p_amount);
END;
$$;

CREATE OR REPLACE FUNCTION expense_account_code(p_category_id bigint)
RETURNS varchar
LANGUAGE sql
STABLE
AS $$
  SELECT CASE lower(coalesce(category_name,''))
    WHEN 'laundry' THEN '501'
    WHEN 'repair' THEN '502'
    WHEN 'electricity' THEN '503'
    WHEN 'listrik' THEN '503'
    WHEN 'internet' THEN '504'
    WHEN 'promotion' THEN '505'
    WHEN 'promosi' THEN '505'
    WHEN 'transportation' THEN '506'
    WHEN 'transportasi' THEN '506'
    WHEN 'rent' THEN '507'
    WHEN 'sewa' THEN '507'
    ELSE '508'
  END
  FROM expense_categories
  WHERE id = p_category_id;
$$;

CREATE OR REPLACE FUNCTION trg_rental_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM post_two_line_journal(
    next_business_code('journal'),
    NEW.rental_date,
    'rental',
    NEW.id,
    'Pendapatan sewa ' || NEW.rental_code,
    '102',
    '401',
    NEW.total_amount
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_rental_journal ON rentals;

CREATE TRIGGER after_rental_journal
AFTER INSERT ON rentals
FOR EACH ROW
EXECUTE FUNCTION trg_rental_journal();

CREATE OR REPLACE FUNCTION trg_purchase_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  credit_code varchar := CASE
    WHEN NEW.payment_status = 'Paid' THEN '101'
    ELSE '201'
  END;
BEGIN
  PERFORM post_two_line_journal(
    next_business_code('journal'),
    NEW.purchase_date,
    'purchase',
    NEW.id,
    'Pembelian dress ' || NEW.purchase_code,
    '103',
    credit_code,
    NEW.total_amount
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_purchase_journal ON purchases;

CREATE TRIGGER after_purchase_journal
AFTER INSERT ON purchases
FOR EACH ROW
EXECUTE FUNCTION trg_purchase_journal();

CREATE OR REPLACE FUNCTION trg_customer_payment_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.payment_type = 'REFUND' THEN
    PERFORM post_two_line_journal(
      next_business_code('journal'),
      NEW.payment_date,
      'rental_refund',
      NEW.id,
      'Refund rental ' || coalesce(NEW.payment_code,''),
      '202',
      '101',
      NEW.amount
    );
  ELSE
    PERFORM post_two_line_journal(
      next_business_code('journal'),
      NEW.payment_date,
      'rental_payment',
      NEW.id,
      'Pembayaran rental ' || coalesce(NEW.payment_code,''),
      '101',
      '102',
      NEW.amount
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION trg_rental_payment_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  rental_total numeric;
  paid_total numeric;
BEGIN
  SELECT coalesce(total_rental, total_amount, 0)
  INTO rental_total
  FROM rentals
  WHERE id = NEW.rental_id;

  SELECT coalesce(
    sum(
      CASE
        WHEN payment_type = 'REFUND' THEN -amount
        ELSE amount
      END
    ),
    0
  )
  INTO paid_total
  FROM payments
  WHERE rental_id = NEW.rental_id;

  UPDATE rentals
  SET
    total_rental = coalesce(total_rental, total_amount),
    payment_status = CASE
      WHEN paid_total <= 0 THEN 'Unpaid'
      WHEN paid_total < rental_total THEN 'Partially Paid'
      ELSE 'Paid'
    END,
    status = CASE
      WHEN rental_status = 'Cancelled' THEN status
      ELSE rental_status
    END
  WHERE id = NEW.rental_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_rental_payment_status ON payments;

CREATE TRIGGER after_rental_payment_status
AFTER INSERT ON payments
FOR EACH ROW
EXECUTE FUNCTION trg_rental_payment_status();

CREATE OR REPLACE FUNCTION trg_payment_status()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION trg_complete_rental()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE rentals
  SET
    rental_status = 'Returned',
    status = 'Completed'
  WHERE id = NEW.rental_id;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION cancel_rental(
  p_rental_id bigint,
  p_reason text,
  p_deposit_action varchar,
  p_cancelled_at timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  rental_row rentals%ROWTYPE;
  paid_amount numeric;
BEGIN
  SELECT *
  INTO rental_row
  FROM rentals
  WHERE id = p_rental_id
  FOR UPDATE;

  IF rental_row.id IS NULL THEN
    RAISE EXCEPTION 'Rental tidak ditemukan';
  END IF;

  IF coalesce(rental_row.rental_status, rental_row.status) IN ('Cancelled','Completed') THEN
    RAISE EXCEPTION 'Rental sudah tidak dapat dibatalkan';
  END IF;

  IF nullif(trim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi';
  END IF;

  SELECT coalesce(sum(amount),0)
  INTO paid_amount
  FROM payments
  WHERE rental_id = p_rental_id
    AND payment_type <> 'REFUND';

  UPDATE rentals
  SET
    rental_status = 'Cancelled',
    status = 'Cancelled',
    cancellation_reason = p_reason,
    cancelled_at = p_cancelled_at
  WHERE id = p_rental_id;

  IF p_deposit_action = 'REFUND' AND paid_amount > 0 THEN
    INSERT INTO payments(
      payment_code,
      rental_id,
      payment_date,
      amount,
      payment_method,
      payment_type,
      notes,
      description
    )
    VALUES(
      next_business_code('payment'),
      p_rental_id,
      p_cancelled_at::date,
      paid_amount,
      'Cash',
      'REFUND',
      'Refund karena pembatalan',
      'Pengembalian DP'
    );

    UPDATE rentals
    SET payment_status = 'Refunded'
    WHERE id = p_rental_id;
  ELSIF p_deposit_action = 'FORFEIT' AND paid_amount > 0 THEN
    PERFORM post_two_line_journal(
      next_business_code('journal'),
      p_cancelled_at::date,
      'rental_cancellation',
      p_rental_id,
      'DP hangus: ' || p_reason,
      '202',
      '403',
      paid_amount
    );
  END IF;

  UPDATE dresses d
  SET status = 'Available'
  WHERE d.id IN (
    SELECT dress_id
    FROM rental_details
    WHERE rental_id = p_rental_id
  )
    AND NOT EXISTS (
      SELECT 1
      FROM rentals r
      JOIN rental_details rd ON rd.rental_id = r.id
      WHERE rd.dress_id = d.id
        AND r.id <> p_rental_id
        AND coalesce(r.rental_status, r.status) IN ('Ongoing','Returned')
    );

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
    'RENTAL_CANCEL',
    p_rental_id,
    rental_row.rental_code,
    'Rented',
    'Available',
    'Dress tersedia kembali setelah rental dibatalkan'
  FROM rental_details rd
  WHERE rd.rental_id = p_rental_id;
END;
$$;

CREATE OR REPLACE FUNCTION create_rental_transaction(
  p_customer_id bigint,
  p_dress_id bigint,
  p_rental_date date,
  p_return_due_date date,
  p_total_rental numeric,
  p_rental_code varchar DEFAULT NULL,
  p_deposit_amount numeric DEFAULT 0,
  p_rental_status varchar DEFAULT 'Booked',
  p_payment_amount numeric DEFAULT 0,
  p_payment_date date DEFAULT current_date,
  p_payment_method varchar DEFAULT 'Cash',
  p_payment_type varchar DEFAULT 'DP'
)
RETURNS TABLE(
  rental_id bigint,
  rental_code varchar,
  payment_code varchar
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  new_rental rentals%ROWTYPE;
  new_payment_code varchar;
  current_dress_status varchar;
BEGIN
  IF p_customer_id IS NULL OR p_dress_id IS NULL THEN
    RAISE EXCEPTION 'Customer dan dress wajib dipilih';
  END IF;

  IF p_return_due_date < p_rental_date THEN
    RAISE EXCEPTION 'Tanggal pengembalian tidak valid';
  END IF;

  IF p_total_rental < 0 OR p_deposit_amount < 0 OR p_payment_amount < 0 THEN
    RAISE EXCEPTION 'Nominal tidak boleh negatif';
  END IF;

  IF p_payment_amount > p_total_rental THEN
    RAISE EXCEPTION 'Pembayaran melebihi total rental';
  END IF;

  IF p_rental_status NOT IN ('Booked','Ongoing') THEN
    RAISE EXCEPTION 'Status rental tidak valid';
  END IF;

  SELECT status
  INTO current_dress_status
  FROM dresses
  WHERE id = p_dress_id
  FOR UPDATE;

  IF current_dress_status IS NULL THEN
    RAISE EXCEPTION 'Dress tidak ditemukan';
  END IF;

  IF current_dress_status <> 'Available' THEN
    RAISE EXCEPTION 'Dress tidak tersedia: status %', current_dress_status;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM rentals r
    JOIN rental_details rd ON rd.rental_id = r.id
    WHERE rd.dress_id = p_dress_id
      AND coalesce(r.rental_status, r.status) NOT IN ('Cancelled','Completed','Returned')
      AND r.rental_date <= p_return_due_date
      AND r.return_due_date >= p_rental_date
  ) THEN
    RAISE EXCEPTION 'Dress tidak tersedia pada periode penyewaan tersebut';
  END IF;

  INSERT INTO rentals(
    rental_code,
    customer_id,
    rental_date,
    return_due_date,
    total_amount,
    total_rental,
    deposit_amount,
    status,
    rental_status,
    payment_status
  )
  VALUES(
    coalesce(p_rental_code, next_business_code('rental')),
    p_customer_id,
    p_rental_date,
    p_return_due_date,
    p_total_rental,
    p_total_rental,
    p_deposit_amount,
    p_rental_status,
    p_rental_status,
    CASE
      WHEN p_payment_amount <= 0 THEN 'Unpaid'
      WHEN p_payment_amount < p_total_rental THEN 'Partially Paid'
      ELSE 'Paid'
    END
  )
  RETURNING * INTO new_rental;

  INSERT INTO rental_details(
    rental_id,
    dress_id,
    rental_price,
    quantity,
    subtotal
  )
  VALUES(
    new_rental.id,
    p_dress_id,
    p_total_rental,
    1,
    p_total_rental
  );

  IF p_payment_amount > 0 THEN
    new_payment_code := next_business_code('payment');

    INSERT INTO payments(
      payment_code,
      rental_id,
      payment_date,
      amount,
      payment_method,
      payment_type,
      notes,
      description
    )
    VALUES(
      new_payment_code,
      new_rental.id,
      p_payment_date,
      p_payment_amount,
      p_payment_method,
      p_payment_type,
      'Pembayaran awal saat transaksi rental',
      'Pembayaran awal rental'
    );
  END IF;

  UPDATE dresses
  SET status = 'Rented'
  WHERE id = p_dress_id;

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
    p_dress_id,
    'RENTAL_OUT',
    new_rental.id,
    new_rental.rental_code,
    'Available',
    'Rented',
    'Dress keluar untuk penyewaan'
  );

  RETURN QUERY
  SELECT
    new_rental.id,
    new_rental.rental_code,
    new_payment_code;
END;
$$;

DROP TRIGGER IF EXISTS after_customer_payment_journal ON payments;

CREATE TRIGGER after_customer_payment_journal
AFTER INSERT ON payments
FOR EACH ROW
EXECUTE FUNCTION trg_customer_payment_journal();

CREATE OR REPLACE FUNCTION trg_purchase_payment_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM post_two_line_journal(
    next_business_code('journal'),
    NEW.payment_date,
    'purchase_payment',
    NEW.id,
    'Pembayaran utang pembelian',
    '201',
    '101',
    NEW.amount
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_purchase_payment_journal ON purchase_payments;

CREATE TRIGGER after_purchase_payment_journal
AFTER INSERT ON purchase_payments
FOR EACH ROW
EXECUTE FUNCTION trg_purchase_payment_journal();

CREATE OR REPLACE FUNCTION trg_expense_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  credit_code varchar := CASE
    WHEN NEW.payment_status = 'Unpaid' THEN '201'
    ELSE '101'
  END;
BEGIN
  PERFORM post_two_line_journal(
    next_business_code('journal'),
    NEW.expense_date,
    'expense',
    NEW.id,
    coalesce(NEW.description, 'Biaya operasional'),
    expense_account_code(NEW.category_id),
    credit_code,
    NEW.amount
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_expense_journal ON expenses;

CREATE TRIGGER after_expense_journal
AFTER INSERT ON expenses
FOR EACH ROW
EXECUTE FUNCTION trg_expense_journal();

CREATE OR REPLACE FUNCTION trg_expense_payment_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM post_two_line_journal(
    next_business_code('journal'),
    NEW.payment_date,
    'expense_payment',
    NEW.id,
    'Pembayaran biaya operasional',
    '201',
    '101',
    NEW.amount
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_expense_payment_journal ON expense_payments;

CREATE TRIGGER after_expense_payment_journal
AFTER INSERT ON expense_payments
FOR EACH ROW
EXECUTE FUNCTION trg_expense_payment_journal();

CREATE OR REPLACE FUNCTION trg_penalty_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM post_two_line_journal(
    next_business_code('journal'),
    now()::date,
    'penalty',
    NEW.id,
    coalesce(NEW.description, 'Denda'),
    '102',
    '402',
    NEW.amount
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_penalty_journal ON penalties;

CREATE TRIGGER after_penalty_journal
AFTER INSERT ON penalties
FOR EACH ROW
EXECUTE FUNCTION trg_penalty_journal();

CREATE OR REPLACE FUNCTION trg_penalty_payment_journal()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM post_two_line_journal(
    next_business_code('journal'),
    NEW.payment_date,
    'penalty_payment',
    NEW.id,
    'Pembayaran denda',
    '101',
    '102',
    NEW.amount
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS after_penalty_payment_journal ON penalty_payments;

CREATE TRIGGER after_penalty_payment_journal
AFTER INSERT ON penalty_payments
FOR EACH ROW
EXECUTE FUNCTION trg_penalty_payment_journal();