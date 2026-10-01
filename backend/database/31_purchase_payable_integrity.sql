-- Derive outstanding supplier debt from effective paid amounts and make
-- purchase-payment posting atomic.
-- Run after 30_variant_inventory_status.sql.

BEGIN;

CREATE OR REPLACE VIEW public.v_purchase_payables WITH (security_invoker = true) AS
WITH paid_by_purchase AS (
  SELECT
    payment.purchase_id,
    sum(payment.amount) AS paid_amount
  FROM public.purchase_payments payment
  GROUP BY payment.purchase_id
),
balances AS (
  SELECT
    purchase.id AS purchase_id,
    purchase.purchase_code,
    purchase.supplier_id,
    supplier.name AS supplier_name,
    purchase.purchase_date,
    purchase.total_amount,
    CASE
      WHEN purchase.payment_status = 'Paid' THEN purchase.total_amount
      ELSE coalesce(paid.paid_amount, 0)
    END AS paid_amount,
    CASE
      WHEN purchase.payment_status = 'Paid' THEN 0
      ELSE greatest(purchase.total_amount - coalesce(paid.paid_amount, 0), 0)
    END AS remaining_amount,
    purchase.payment_status
  FROM public.purchases purchase
  LEFT JOIN public.suppliers supplier
    ON supplier.id = purchase.supplier_id
  LEFT JOIN paid_by_purchase paid
    ON paid.purchase_id = purchase.id
)
SELECT *
FROM balances
WHERE remaining_amount > 0;

REVOKE ALL ON public.v_purchase_payables FROM PUBLIC, anon;
GRANT SELECT ON public.v_purchase_payables TO authenticated;

CREATE OR REPLACE FUNCTION public.record_purchase_payment(
  p_purchase_id bigint,
  p_payment_date date,
  p_amount numeric,
  p_payment_method varchar,
  p_description text DEFAULT NULL
)
RETURNS public.purchase_payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  purchase_row public.purchases%ROWTYPE;
  paid_amount numeric;
  outstanding numeric;
  new_payment public.purchase_payments%ROWTYPE;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff', 'accounting') THEN
    RAISE EXCEPTION 'Role tidak diizinkan membayar utang supplier';
  END IF;

  SELECT *
  INTO purchase_row
  FROM public.purchases
  WHERE id = p_purchase_id
  FOR UPDATE;

  IF purchase_row.id IS NULL THEN
    RAISE EXCEPTION 'Pembelian tidak ditemukan';
  END IF;

  IF purchase_row.payment_status = 'Paid' THEN
    RAISE EXCEPTION 'Pembelian sudah lunas';
  END IF;

  IF p_payment_date IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Tanggal dan nominal pembayaran wajib valid';
  END IF;

  IF p_payment_method IS NULL
    OR p_payment_method NOT IN ('Cash', 'Transfer', 'E-Wallet')
  THEN
    RAISE EXCEPTION 'Metode pembayaran tidak valid';
  END IF;

  SELECT coalesce(sum(payment.amount), 0)
  INTO paid_amount
  FROM public.purchase_payments payment
  WHERE payment.purchase_id = p_purchase_id;

  outstanding := greatest(purchase_row.total_amount - paid_amount, 0);

  IF outstanding <= 0 THEN
    RAISE EXCEPTION 'Pembelian sudah lunas';
  END IF;

  IF p_amount > outstanding THEN
    RAISE EXCEPTION 'Pembayaran melebihi sisa utang';
  END IF;

  INSERT INTO public.purchase_payments(
    purchase_id,
    payment_date,
    amount,
    payment_method,
    description
  )
  VALUES (
    p_purchase_id,
    p_payment_date,
    p_amount,
    p_payment_method,
    p_description
  )
  RETURNING * INTO new_payment;

  UPDATE public.purchases
  SET payment_status = CASE
    WHEN paid_amount + p_amount >= purchase_row.total_amount THEN 'Paid'
    ELSE 'Partially Paid'
  END
  WHERE id = p_purchase_id;

  RETURN new_payment;
END;
$$;

REVOKE ALL
ON FUNCTION public.record_purchase_payment(bigint, date, numeric, varchar, text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.record_purchase_payment(bigint, date, numeric, varchar, text)
TO authenticated;

REVOKE INSERT, UPDATE, DELETE
ON public.purchase_payments
FROM authenticated;

GRANT SELECT
ON public.purchase_payments
TO authenticated;

REVOKE INSERT, UPDATE, DELETE
ON public.purchases
FROM authenticated;

REVOKE ALL
ON FUNCTION public.next_business_code(text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.next_business_code(text)
TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;