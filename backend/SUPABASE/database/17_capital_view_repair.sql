-- Repair the canonical capital reporting view after migration 13.
-- This does not create a duplicate source table.

DO $$
BEGIN
  IF to_regclass('public.capital_contributions') IS NULL THEN
    RAISE EXCEPTION 'Tabel public.capital_contributions belum ada. Jalankan 13_capital_contribution.sql terlebih dahulu.';
  END IF;
END;
$$;

-- The table may have been created by an older deployment with fewer columns.
-- ADD COLUMN IF NOT EXISTS preserves existing rows and makes the view contract explicit.

ALTER TABLE public.capital_contributions
  ADD COLUMN IF NOT EXISTS capital_code varchar(30);

ALTER TABLE public.capital_contributions
  ADD COLUMN IF NOT EXISTS contribution_date date NOT NULL DEFAULT current_date;

ALTER TABLE public.capital_contributions
  ADD COLUMN IF NOT EXISTS owner_name varchar(150) NOT NULL DEFAULT 'Pemilik';

ALTER TABLE public.capital_contributions
  ADD COLUMN IF NOT EXISTS contribution_type varchar(30) NOT NULL DEFAULT 'Cash';

ALTER TABLE public.capital_contributions
  ADD COLUMN IF NOT EXISTS cash_account_id bigint REFERENCES public.accounts(id);

ALTER TABLE public.capital_contributions
  ADD COLUMN IF NOT EXISTS amount numeric(15,2) NOT NULL DEFAULT 0;

ALTER TABLE public.capital_contributions
  ADD COLUMN IF NOT EXISTS description text;

ALTER TABLE public.capital_contributions
  ADD COLUMN IF NOT EXISTS status varchar(20) NOT NULL DEFAULT 'Posted';

ALTER TABLE public.capital_contributions
  ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id);

ALTER TABLE public.capital_contributions
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();

CREATE SEQUENCE IF NOT EXISTS capital_number_seq START WITH 1;

SELECT setval(
  'capital_number_seq',
  coalesce(
    (
      SELECT max(substring(capital_code from 5)::bigint)
      FROM public.capital_contributions
      WHERE capital_code ~ '^MOD-[0-9]+$'
    ),
    0
  ) + 1,
  false
);

UPDATE public.capital_contributions
SET capital_code = 'MOD-' || lpad(nextval('capital_number_seq')::text, 4, '0')
WHERE capital_code IS NULL
  OR nullif(trim(capital_code), '') IS NULL;

DROP VIEW IF EXISTS public.v_capital_contributions;

CREATE VIEW public.v_capital_contributions AS
SELECT
  c.id,
  c.capital_code,
  c.contribution_date,
  c.owner_name,
  c.contribution_type,
  c.cash_account_id AS account_id,
  a.account_code,
  a.account_name,
  c.amount,
  c.description,
  c.status,
  c.created_by,
  c.created_at
FROM public.capital_contributions c
LEFT JOIN public.accounts a ON a.id = c.cash_account_id;

GRANT SELECT ON public.v_capital_contributions TO authenticated;

NOTIFY pgrst, 'reload schema';