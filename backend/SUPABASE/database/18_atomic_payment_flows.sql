-- Atomic rental and expense payment flows.
-- Run after 17_capital_view_repair.sql.

CREATE OR REPLACE FUNCTION record_rental_payment(
  p_rental_id bigint,
  p_payment_date date,
  p_amount numeric,
  p_payment_method varchar,
  p_payment_type varchar DEFAULT 'PELUNASAN',
  p_payment_reference varchar DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rental_row rentals%ROWTYPE;
  paid_amount numeric;
  outstanding numeric;
  new_payment payments%ROWTYPE;
BEGIN
  SELECT *
  INTO rental_row
  FROM rentals
  WHERE id = p_rental_id
  FOR UPDATE;

  IF rental_row.id IS NULL THEN
    RAISE EXCEPTION 'Rental tidak ditemukan';
  END IF;

  IF coalesce(rental_row.rental_status,rental_row.status) = 'Cancelled'
    OR rental_row.status = 'Cancelled'
  THEN
    RAISE EXCEPTION 'Rental dibatalkan dan tidak dapat menerima pembayaran';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Nominal pembayaran harus lebih besar dari nol';
  END IF;

  IF p_payment_method NOT IN ('Cash','Transfer','Transfer Bank','E-Wallet','QRIS','Lainnya') THEN
    RAISE EXCEPTION 'Metode pembayaran tidak valid';
  END IF;

  SELECT coalesce(
    sum(
      CASE
        WHEN payment_type = 'REFUND' THEN -amount
        ELSE amount
      END
    ),
    0
  )
  INTO paid_amount
  FROM payments
  WHERE rental_id = p_rental_id;

  outstanding := greatest(
    coalesce(rental_row.total_rental,rental_row.total_amount,0) - paid_amount,
    0
  );

  IF outstanding <= 0 THEN
    RAISE EXCEPTION 'Rental sudah lunas';
  END IF;

  IF p_amount > outstanding THEN
    RAISE EXCEPTION 'Pembayaran melebihi sisa tagihan';
  END IF;

  INSERT INTO payments(
    rental_id,
    payment_date,
    amount,
    payment_method,
    payment_type,
    payment_reference,
    notes,
    description
  )
  VALUES(
    p_rental_id,
    p_payment_date,
    p_amount,
    p_payment_method,
    p_payment_type,
    p_payment_reference,
    p_notes,
    'Pembayaran rental'
  )
  RETURNING * INTO new_payment;

  RETURN new_payment;
END;
$$;

GRANT EXECUTE ON FUNCTION record_rental_payment(bigint,date,numeric,varchar,varchar,varchar,text) TO authenticated;

CREATE OR REPLACE FUNCTION record_expense_payment(
  p_expense_id bigint,
  p_payment_date date,
  p_amount numeric,
  p_payment_method varchar DEFAULT 'Cash',
  p_description text DEFAULT NULL
)
RETURNS expense_payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  expense_row expenses%ROWTYPE;
  paid_amount numeric;
  outstanding numeric;
  new_payment expense_payments%ROWTYPE;
BEGIN
  SELECT *
  INTO expense_row
  FROM expenses
  WHERE id = p_expense_id
  FOR UPDATE;

  IF expense_row.id IS NULL THEN
    RAISE EXCEPTION 'Biaya operasional tidak ditemukan';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Nominal pembayaran harus lebih besar dari nol';
  END IF;

  SELECT coalesce(sum(amount),0)
  INTO paid_amount
  FROM expense_payments
  WHERE expense_id = p_expense_id;

  outstanding := greatest(expense_row.amount - paid_amount,0);

  IF outstanding <= 0 THEN
    RAISE EXCEPTION 'Biaya operasional sudah lunas';
  END IF;

  IF p_amount > outstanding THEN
    RAISE EXCEPTION 'Pembayaran melebihi sisa biaya operasional';
  END IF;

  INSERT INTO expense_payments(
    expense_id,
    payment_date,
    amount,
    payment_method,
    description
  )
  VALUES(
    p_expense_id,
    p_payment_date,
    p_amount,
    p_payment_method,
    p_description
  )
  RETURNING * INTO new_payment;

  UPDATE expenses
  SET payment_status = CASE
    WHEN p_amount + paid_amount >= expense_row.amount THEN 'Paid'
    ELSE 'Partially Paid'
  END
  WHERE id = p_expense_id;

  RETURN new_payment;
END;
$$;

GRANT EXECUTE ON FUNCTION record_expense_payment(bigint,date,numeric,varchar,text) TO authenticated;

NOTIFY pgrst, 'reload schema';