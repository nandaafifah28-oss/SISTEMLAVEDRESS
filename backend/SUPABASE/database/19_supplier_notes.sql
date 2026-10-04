-- Optional supplier notes for the inline purchase supplier form.
-- Run after 18_atomic_payment_flows.sql.

ALTER TABLE public.suppliers
  ADD COLUMN IF NOT EXISTS notes text;

NOTIFY pgrst, 'reload schema';