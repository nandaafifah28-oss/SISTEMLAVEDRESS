-- Accounting reporting layer derived only from journal_entries,
-- journal_details, and accounts.

DROP VIEW IF EXISTS public.v_general_ledger CASCADE;
DROP VIEW IF EXISTS public.v_trial_balance CASCADE;
DROP VIEW IF EXISTS public.v_income_statement CASCADE;
DROP VIEW IF EXISTS public.v_balance_sheet CASCADE;
DROP VIEW IF EXISTS public.v_cash_flow CASCADE;

CREATE OR REPLACE VIEW public.v_general_ledger AS
SELECT
  jd.id AS journal_detail_id,
  je.id AS journal_entry_id,
  je.journal_code AS journal_number,
  je.journal_date,
  je.reference_type,
  je.reference_id,
  je.description AS journal_description,
  a.id AS account_id,
  a.account_code,
  a.account_name,
  a.account_type,
  CASE
    WHEN a.account_type IN ('Asset', 'Expense') THEN 'Debit'
    ELSE 'Credit'
  END AS normal_balance,
  jd.debit,
  jd.credit,
  CASE
    WHEN a.account_type IN ('Asset', 'Expense') THEN jd.debit - jd.credit
    ELSE jd.credit - jd.debit
  END AS signed_amount
FROM public.journal_details jd
JOIN public.journal_entries je ON je.id = jd.journal_id
JOIN public.accounts a ON a.id = jd.account_id;

CREATE OR REPLACE VIEW public.v_trial_balance AS
SELECT
  a.id AS account_id,
  a.account_code,
  a.account_name,
  a.account_type,
  CASE
    WHEN a.account_type IN ('Asset', 'Expense') THEN 'Debit'
    ELSE 'Credit'
  END AS normal_balance,
  coalesce(sum(jd.debit), 0) AS total_debit,
  coalesce(sum(jd.credit), 0) AS total_credit,
  CASE
    WHEN a.account_type IN ('Asset', 'Expense') THEN coalesce(sum(jd.debit - jd.credit), 0)
    ELSE coalesce(sum(jd.credit - jd.debit), 0)
  END AS balance
FROM public.accounts a
LEFT JOIN public.journal_details jd ON jd.account_id = a.id
LEFT JOIN public.journal_entries je ON je.id = jd.journal_id
GROUP BY a.id, a.account_code, a.account_name, a.account_type
ORDER BY a.account_code;

CREATE OR REPLACE VIEW public.v_income_statement AS
SELECT
  a.id AS account_id,
  a.account_code,
  a.account_name,
  a.account_type,
  CASE
    WHEN a.account_type = 'Revenue' THEN coalesce(sum(jd.credit - jd.debit), 0)
    ELSE coalesce(sum(jd.debit - jd.credit), 0)
  END AS amount
FROM public.accounts a
LEFT JOIN public.journal_details jd ON jd.account_id = a.id
LEFT JOIN public.journal_entries je ON je.id = jd.journal_id
WHERE a.account_type IN ('Revenue', 'Expense')
GROUP BY a.id, a.account_code, a.account_name, a.account_type
ORDER BY a.account_code;

CREATE OR REPLACE VIEW public.v_balance_sheet AS
SELECT
  a.id AS account_id,
  a.account_code,
  a.account_name,
  a.account_type,
  CASE
    WHEN a.account_type IN ('Asset', 'Expense') THEN coalesce(sum(jd.debit - jd.credit), 0)
    ELSE coalesce(sum(jd.credit - jd.debit), 0)
  END AS balance
FROM public.accounts a
LEFT JOIN public.journal_details jd ON jd.account_id = a.id
LEFT JOIN public.journal_entries je ON je.id = jd.journal_id
WHERE a.account_type IN ('Asset', 'Liability', 'Equity')
GROUP BY a.id, a.account_code, a.account_name, a.account_type
ORDER BY a.account_code;

CREATE OR REPLACE VIEW public.v_cash_flow AS
SELECT
  je.journal_date,
  je.journal_code AS journal_number,
  je.reference_type,
  je.reference_id,
  je.description,
  CASE
    WHEN jd.debit > 0 THEN jd.debit
    ELSE 0
  END AS cash_in,
  CASE
    WHEN jd.credit > 0 THEN jd.credit
    ELSE 0
  END AS cash_out
FROM public.journal_entries je
JOIN public.journal_details jd ON jd.journal_id = je.id
JOIN public.accounts a ON a.id = jd.account_id
WHERE a.account_code = '101';

NOTIFY pgrst, 'reload schema';