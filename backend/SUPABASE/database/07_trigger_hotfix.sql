-- Run this file first when Supabase still reports assign_transaction_codes().
-- It removes the stale polymorphic trigger from the deployed database.

DROP TRIGGER IF EXISTS assign_customer_code ON customers;
DROP TRIGGER IF EXISTS assign_supplier_code ON suppliers;
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

CREATE SEQUENCE IF NOT EXISTS customer_number_seq START WITH 1;
CREATE SEQUENCE IF NOT EXISTS supplier_number_seq START WITH 1;

SELECT setval(
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

SELECT setval(
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

CREATE OR REPLACE FUNCTION next_customer_code()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 'CUS-' || lpad(nextval('customer_number_seq')::text, 4, '0');
$$;

CREATE OR REPLACE FUNCTION next_supplier_code()
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 'SUP-' || lpad(nextval('supplier_number_seq')::text, 4, '0');
$$;

CREATE OR REPLACE FUNCTION assign_customer_code_safe()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.customer_code, '') IS NULL THEN
    NEW.customer_code := next_customer_code();
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION assign_supplier_code_safe()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF nullif(NEW.supplier_code, '') IS NULL THEN
    NEW.supplier_code := next_supplier_code();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assign_customer_code ON customers;

CREATE TRIGGER assign_customer_code
BEFORE INSERT ON customers
FOR EACH ROW
EXECUTE FUNCTION assign_customer_code_safe();

DROP TRIGGER IF EXISTS assign_supplier_code ON suppliers;

CREATE TRIGGER assign_supplier_code
BEFORE INSERT ON suppliers
FOR EACH ROW
EXECUTE FUNCTION assign_supplier_code_safe();