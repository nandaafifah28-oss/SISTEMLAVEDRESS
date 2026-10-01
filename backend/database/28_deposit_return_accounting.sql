-- Separate rental deposits from rent payments and allocate deposits on return.
-- Run after 27_purchase_dress_id_ambiguity_fix.sql.

BEGIN;

ALTER TABLE public.rentals
  ADD COLUMN IF NOT EXISTS deposit_received_amount numeric(15,2) NOT NULL DEFAULT 0
  CHECK (deposit_received_amount >= 0);

ALTER TABLE public.returns
  ADD COLUMN IF NOT EXISTS deposit_used numeric(15,2) NOT NULL DEFAULT 0 CHECK (deposit_used >= 0),
  ADD COLUMN IF NOT EXISTS deposit_refunded numeric(15,2) NOT NULL DEFAULT 0 CHECK (deposit_refunded >= 0),
  ADD COLUMN IF NOT EXISTS customer_receivable numeric(15,2) NOT NULL DEFAULT 0 CHECK (customer_receivable >= 0);

-- Existing open rentals treated deposit_amount as money already held. Record
-- that opening liability once; closed rentals are not guessed or rewritten.

UPDATE public.rentals rental
SET deposit_received_amount = coalesce(rental.deposit_amount, 0)
WHERE NOT EXISTS (
  SELECT 1
  FROM public.returns returned
  WHERE returned.rental_id = rental.id
)
  AND coalesce(rental.rental_status, rental.status) NOT IN ('Cancelled', 'Completed', 'Returned')
  AND rental.status NOT IN ('Cancelled', 'Completed')
  AND rental.deposit_received_amount = 0;

DO $$
DECLARE
  rental_row record;
BEGIN
  FOR rental_row IN
    SELECT
      rental.id,
      rental.rental_code,
      rental.deposit_received_amount
    FROM public.rentals rental
    WHERE rental.deposit_received_amount > 0
      AND NOT EXISTS (
        SELECT 1
        FROM public.journal_entries journal
        WHERE journal.reference_type IN ('deposit_migration_opening', 'rental_deposit')
          AND journal.reference_id = rental.id
      )
  LOOP
    PERFORM public.post_two_line_journal(
      public.next_business_code('journal'),
      current_date,
      'deposit_migration_opening',
      rental_row.id,
      'Saldo pembuka deposit customer ' || rental_row.rental_code,
      '101',
      '202',
      rental_row.deposit_received_amount
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_rental_deposit_received()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.deposit_received_amount := coalesce(NEW.deposit_amount, 0);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_rental_deposit_received ON public.rentals;

CREATE TRIGGER set_rental_deposit_received
BEFORE INSERT ON public.rentals
FOR EACH ROW
EXECUTE FUNCTION public.set_rental_deposit_received();

CREATE OR REPLACE FUNCTION public.record_new_rental_deposit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.deposit_received_amount > 0 THEN
    PERFORM public.post_two_line_journal(
      public.next_business_code('journal'),
      NEW.rental_date,
      'rental_deposit',
      NEW.id,
      'Penerimaan deposit ' || NEW.rental_code,
      '101',
      '202',
      NEW.deposit_received_amount
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS record_new_rental_deposit ON public.rentals;

CREATE TRIGGER record_new_rental_deposit
AFTER INSERT ON public.rentals
FOR EACH ROW
EXECUTE FUNCTION public.record_new_rental_deposit();

CREATE OR REPLACE FUNCTION public.trg_customer_payment_journal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.payment_type = 'REFUND' THEN
    PERFORM public.post_two_line_journal(
      public.next_business_code('journal'),
      NEW.payment_date,
      'rental_refund',
      NEW.id,
      'Refund pembayaran sewa ' || coalesce(NEW.payment_code, ''),
      '102',
      '101',
      NEW.amount
    );
  ELSE
    PERFORM public.post_two_line_journal(
      public.next_business_code('journal'),
      NEW.payment_date,
      'rental_payment',
      NEW.id,
      'Pembayaran rental ' || coalesce(NEW.payment_code, ''),
      '101',
      '102',
      NEW.amount
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_rental_payment_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rental_total numeric;
  paid_total numeric;
BEGIN
  SELECT coalesce(total_rental, total_amount, 0)
  INTO rental_total
  FROM public.rentals
  WHERE id = NEW.rental_id;

  SELECT coalesce(
    sum(
      CASE
        WHEN payment_type = 'REFUND' THEN -amount
        WHEN payment_type IN ('DP', 'PELUNASAN') THEN amount
        ELSE 0
      END
    ),
    0
  )
  INTO paid_total
  FROM public.payments
  WHERE rental_id = NEW.rental_id;

  UPDATE public.rentals
  SET total_rental = coalesce(total_rental, total_amount),
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

CREATE OR REPLACE FUNCTION public.trg_penalty_journal()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deposit_used_value numeric;
  customer_receivable_value numeric;
  return_date_value date;
BEGIN
  SELECT
    returned.deposit_used,
    returned.customer_receivable,
    returned.return_date
  INTO
    deposit_used_value,
    customer_receivable_value,
    return_date_value
  FROM public.returns returned
  WHERE returned.id = NEW.return_id;

  IF coalesce(deposit_used_value, 0) > 0 THEN
    PERFORM public.post_two_line_journal(
      public.next_business_code('journal'),
      return_date_value,
      'penalty_deposit',
      NEW.id,
      'Denda dibayar dari deposit',
      '202',
      '402',
      deposit_used_value
    );
  END IF;

  IF coalesce(customer_receivable_value, 0) > 0 THEN
    PERFORM public.post_two_line_journal(
      public.next_business_code('journal'),
      return_date_value,
      'penalty_receivable',
      NEW.id,
      coalesce(NEW.description, 'Piutang denda customer'),
      '102',
      '402',
      customer_receivable_value
    );
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.process_return_transaction(
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
  rental_row public.rentals%ROWTYPE;
    new_return public.returns%ROWTYPE;
  new_penalty public.penalties%ROWTYPE;
  new_payment public.penalty_payments%ROWTYPE;
  new_penalty_id bigint;
  new_payment_id bigint;
  late_days_value integer;
  late_amount numeric;
  total_amount numeric;
  deposit_value numeric;
  deposit_used_value numeric;
  deposit_refunded_value numeric;
  customer_receivable_value numeric;
  damage_value numeric := greatest(coalesce(p_damage_amount, 0), 0);
  payment_value numeric := greatest(coalesce(p_payment_amount, 0), 0);
  detail_row record;
  mapped_condition varchar;
  next_status varchar;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff', 'accounting') THEN
    RAISE EXCEPTION 'Role tidak diizinkan memproses return';
  END IF;

  SELECT *
  INTO rental_row
  FROM public.rentals
  WHERE id = p_rental_id
  FOR UPDATE;

  IF rental_row.id IS NULL THEN
    RAISE EXCEPTION 'Rental tidak ditemukan';
  END IF;

  IF p_return_date IS NULL THEN
    RAISE EXCEPTION 'Tanggal pengembalian wajib diisi';
  END IF;

  IF p_condition IS NULL
    OR p_condition NOT IN ('Baik', 'Kotor', 'Rusak Ringan', 'Rusak Berat', 'Hilang')
  THEN
    RAISE EXCEPTION 'Kondisi pengembalian tidak valid';
  END IF;

  IF coalesce(p_late_rate, 0) < 0
    OR coalesce(p_damage_amount, 0) < 0
    OR coalesce(p_payment_amount, 0) < 0
  THEN
    RAISE EXCEPTION 'Nominal denda tidak boleh negatif';
  END IF;

  IF payment_value > 0
    AND (
      p_payment_method IS NULL
      OR p_payment_method NOT IN ('Cash', 'Transfer', 'E-Wallet')
    )
  THEN
    RAISE EXCEPTION 'Metode pembayaran denda tidak valid';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.returns
    WHERE rental_id = p_rental_id
  ) THEN
    RAISE EXCEPTION 'Rental sudah memiliki pengembalian';
  END IF;

  IF coalesce(rental_row.rental_status, rental_row.status) IN ('Returned', 'Completed', 'Cancelled')
    OR rental_row.status IN ('Completed', 'Cancelled')
  THEN
    RAISE EXCEPTION 'Rental berstatus % tidak dapat dikembalikan',
      coalesce(rental_row.rental_status, rental_row.status);
  END IF;

  late_days_value := greatest(0, p_return_date - rental_row.return_due_date);
  late_amount := late_days_value * coalesce(p_late_rate, 0);
  total_amount := late_amount + damage_value;
  deposit_value := coalesce(rental_row.deposit_received_amount, 0);
  deposit_used_value := least(deposit_value, total_amount);
  deposit_refunded_value := greatest(deposit_value - total_amount, 0);
  customer_receivable_value := greatest(total_amount - deposit_used_value, 0);

  IF payment_value > customer_receivable_value THEN
    RAISE EXCEPTION 'Pembayaran melebihi sisa denda setelah deposit';
  END IF;

  INSERT INTO public.returns(
    rental_id,
    return_date,
    condition,
    late_days,
    notes,
    late_rate,
    late_penalty,
    damage_amount,
    total_penalty,
    penalty_payment_status,
    deposit_used,
    deposit_refunded,
    customer_receivable
  )
  VALUES (
    p_rental_id,
    p_return_date,
    p_condition,
    late_days_value,
    p_notes,
    coalesce(p_late_rate, 0),
    late_amount,
    damage_value,
    total_amount,
    CASE
      WHEN customer_receivable_value = 0
        OR payment_value >= customer_receivable_value
      THEN 'Paid'
      WHEN payment_value = 0 THEN 'Unpaid'
      ELSE 'Partially Paid'
    END,
    deposit_used_value,
    deposit_refunded_value,
    customer_receivable_value
  )
  RETURNING * INTO new_return;

  mapped_condition := CASE p_condition
    WHEN 'Baik' THEN 'Good'
    ELSE p_condition
  END;

  FOR detail_row IN
    SELECT
      detail.dress_id,
      detail.dress_variant_id,
      detail.quantity,
      variant.status AS previous_status,
      variant.condition AS previous_condition,
      variant.quantity,
      variant.available_quantity,
      variant.rented_quantity,
      variant.unavailable_quantity,
      variant.size
    FROM public.rental_details detail
    JOIN public.dress_variants variant
      ON variant.id = detail.dress_variant_id
    WHERE detail.rental_id = p_rental_id
    FOR UPDATE OF variant
  LOOP
    IF detail_row.rented_quantity < detail_row.quantity THEN
      RAISE EXCEPTION 'Jumlah unit disewa tidak konsisten untuk varian %',
        detail_row.dress_variant_id;
    END IF;

    UPDATE public.dress_variants
    SET rented_quantity = rented_quantity - detail_row.quantity,
        available_quantity = available_quantity + CASE
          WHEN p_condition = 'Baik' AND detail_row.size <> 'UNKNOWN'
          THEN detail_row.quantity
          ELSE 0
        END,
        unavailable_quantity = unavailable_quantity + CASE
          WHEN p_condition = 'Baik' AND detail_row.size <> 'UNKNOWN'
          THEN 0
          ELSE detail_row.quantity
        END,
        condition = CASE
          WHEN detail_row.size = 'UNKNOWN' THEN 'Unknown Size'
          ELSE CASE
            WHEN quantity = detail_row.quantity THEN mapped_condition
            WHEN condition = mapped_condition THEN condition
            ELSE 'Mixed'
          END
        END,
        status = CASE
          WHEN available_quantity + CASE
            WHEN p_condition = 'Baik' AND detail_row.size <> 'UNKNOWN'
            THEN detail_row.quantity
            ELSE 0
          END > 0 THEN 'Available'
          WHEN rented_quantity - detail_row.quantity > 0 THEN 'Rented'
          WHEN detail_row.size = 'UNKNOWN' THEN 'Unknown Size'
          WHEN p_condition = 'Kotor' THEN 'Laundry'
          WHEN p_condition = 'Rusak Ringan' THEN 'Repair'
          ELSE 'Not Available'
        END,
        updated_at = now()
    WHERE id = detail_row.dress_variant_id
    RETURNING status INTO next_status;

    INSERT INTO public.dress_movements(
      dress_id,
      dress_variant_id,
      movement_type,
      reference_id,
      reference_code,
      status_before,
      status_after,
      quantity_delta,
      available_delta,
      rented_delta,
      unavailable_delta,
      description
    )
    VALUES (
      detail_row.dress_id,
      detail_row.dress_variant_id,
      'RETURN',
      new_return.id,
      new_return.return_code,
      detail_row.previous_status,
      next_status,
      0,
      CASE
        WHEN p_condition = 'Baik' AND detail_row.size <> 'UNKNOWN'
        THEN detail_row.quantity
        ELSE 0
      END,
      -detail_row.quantity,
      CASE
        WHEN p_condition = 'Baik' AND detail_row.size <> 'UNKNOWN'
        THEN 0
        ELSE detail_row.quantity
      END,
      'Unit ukuran kembali dari pengembalian'
    );
  END LOOP;

  IF total_amount > 0 THEN
    INSERT INTO public.penalties(
      return_id,
      penalty_type,
      amount,
      description
    )
    VALUES (
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
      INSERT INTO public.penalty_payments(
        penalty_id,
        payment_date,
        amount,
        payment_method,
        description
      )
      VALUES (
        new_penalty.id,
        p_return_date,
        payment_value,
        p_payment_method,
        'Pembayaran sisa denda saat pengembalian'
      )
      RETURNING * INTO new_payment;

      new_payment_id := new_payment.id;
    END IF;
  END IF;

  IF deposit_refunded_value > 0 THEN
    PERFORM public.post_two_line_journal(
      public.next_business_code('journal'),
      p_return_date,
      'deposit_refund',
      new_return.id,
      'Pengembalian sisa deposit ' || rental_row.rental_code,
      '202',
      '101',
      deposit_refunded_value
    );
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

REVOKE ALL
ON FUNCTION public.process_return_transaction(
  bigint,
  date,
  varchar,
  text,
  numeric,
  numeric,
  numeric,
  varchar
)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.process_return_transaction(
  bigint,
  date,
  varchar,
  text,
  numeric,
  numeric,
  numeric,
  varchar
)
TO authenticated;

CREATE OR REPLACE FUNCTION public.record_rental_payment(
  p_rental_id bigint,
  p_payment_date date,
  p_amount numeric,
  p_payment_method varchar,
  p_payment_type varchar DEFAULT 'PELUNASAN',
  p_payment_reference varchar DEFAULT NULL,
  p_notes text DEFAULT NULL
)
RETURNS public.payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rental_row public.rentals%ROWTYPE;
  paid_amount numeric;
  outstanding numeric;
  new_payment public.payments%ROWTYPE;
  BEGIN
  IF current_app_role() NOT IN ('admin', 'staff', 'accounting') THEN
    RAISE EXCEPTION 'Role tidak diizinkan mencatat pembayaran';
  END IF;

  SELECT *
  INTO rental_row
  FROM public.rentals
  WHERE id = p_rental_id
  FOR UPDATE;

  IF rental_row.id IS NULL THEN
    RAISE EXCEPTION 'Rental tidak ditemukan';
  END IF;

  IF coalesce(rental_row.rental_status, rental_row.status) = 'Cancelled'
    OR rental_row.status = 'Cancelled'
  THEN
    RAISE EXCEPTION 'Rental dibatalkan dan tidak dapat menerima pembayaran';
  END IF;

  IF p_payment_date IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Tanggal dan nominal pembayaran wajib valid';
  END IF;

  IF p_payment_method IS NULL
    OR p_payment_method NOT IN ('Cash', 'Transfer', 'Transfer Bank', 'E-Wallet', 'QRIS', 'Lainnya')
  THEN
    RAISE EXCEPTION 'Metode pembayaran tidak valid';
  END IF;

  IF p_payment_type IS NULL OR p_payment_type NOT IN ('DP', 'PELUNASAN') THEN
    RAISE EXCEPTION 'Tipe pembayaran sewa tidak valid';
  END IF;

  SELECT coalesce(
    sum(
      CASE
        WHEN payment_type = 'REFUND' THEN -amount
        WHEN payment_type IN ('DP', 'PELUNASAN') THEN amount
        ELSE 0
      END
    ),
    0
  )
  INTO paid_amount
  FROM public.payments
  WHERE rental_id = p_rental_id;

  outstanding := greatest(
    coalesce(rental_row.total_rental, rental_row.total_amount, 0) - paid_amount,
    0
  );

  IF outstanding <= 0 THEN
    RAISE EXCEPTION 'Rental sudah lunas';
  END IF;

  IF p_amount > outstanding THEN
    RAISE EXCEPTION 'Pembayaran melebihi sisa tagihan sewa';
  END IF;

  INSERT INTO public.payments(
    rental_id,
    payment_date,
    amount,
    payment_method,
    payment_type,
    payment_reference,
    notes,
    description
  )
  VALUES (
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

REVOKE ALL
ON FUNCTION public.record_rental_payment(bigint,date,numeric,varchar,varchar,varchar,text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.record_rental_payment(bigint,date,numeric,varchar,varchar,varchar,text)
TO authenticated;

CREATE OR REPLACE FUNCTION public.record_expense_payment(
  p_expense_id bigint,
  p_payment_date date,
  p_amount numeric,
  p_payment_method varchar DEFAULT 'Cash',
  p_description text DEFAULT NULL
)
RETURNS public.expense_payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  expense_row public.expenses%ROWTYPE;
  paid_amount numeric;
  outstanding numeric;
  new_payment public.expense_payments%ROWTYPE;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff', 'accounting') THEN
    RAISE EXCEPTION 'Role tidak diizinkan mencatat pembayaran biaya';
  END IF;

  SELECT *
  INTO expense_row
  FROM public.expenses
  WHERE id = p_expense_id
  FOR UPDATE;

  IF expense_row.id IS NULL THEN
    RAISE EXCEPTION 'Biaya operasional tidak ditemukan';
  END IF;

  IF p_payment_date IS NULL OR p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Tanggal dan nominal pembayaran wajib valid';
  END IF;

  IF p_payment_method IS NULL
    OR p_payment_method NOT IN ('Cash', 'Transfer', 'E-Wallet')
  THEN
    RAISE EXCEPTION 'Metode pembayaran tidak valid';
  END IF;

  SELECT coalesce(sum(amount), 0)
  INTO paid_amount
  FROM public.expense_payments
  WHERE expense_id = p_expense_id;

  outstanding := greatest(expense_row.amount - paid_amount, 0);

  IF outstanding <= 0 THEN
    RAISE EXCEPTION 'Biaya operasional sudah lunas';
  END IF;

  IF p_amount > outstanding THEN
    RAISE EXCEPTION 'Pembayaran melebihi sisa biaya operasional';
  END IF;

  INSERT INTO public.expense_payments(
    expense_id,
    payment_date,
    amount,
    payment_method,
    description
  )
  VALUES (
    p_expense_id,
    p_payment_date,
    p_amount,
    p_payment_method,
    p_description
  )
  RETURNING * INTO new_payment;

  UPDATE public.expenses
  SET payment_status = CASE
    WHEN paid_amount + p_amount >= expense_row.amount THEN 'Paid'
    ELSE 'Partially Paid'
  END
  WHERE id = p_expense_id;

  RETURN new_payment;
END;
$$;

REVOKE ALL
ON FUNCTION public.record_expense_payment(bigint,date,numeric,varchar,text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.record_expense_payment(bigint,date,numeric,varchar,text)
TO authenticated;

CREATE OR REPLACE FUNCTION public.record_penalty_payment(
  p_penalty_id bigint,
  p_payment_date date,
  p_amount numeric,
  p_payment_method varchar DEFAULT 'Cash',
  p_description text DEFAULT NULL
)
RETURNS public.penalty_payments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  penalty_row record;
  paid_amount numeric;
  outstanding numeric;
  new_payment public.penalty_payments%ROWTYPE;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff', 'accounting') THEN
    RAISE EXCEPTION 'Role tidak diizinkan mencatat pembayaran denda';
  END IF;

  SELECT
    penalty.id,
    penalty.amount,
    penalty.return_id,
    coalesce(returned.deposit_used, 0) AS deposit_used
  INTO penalty_row
  FROM public.penalties penalty
  JOIN public.returns returned
    ON returned.id = penalty.return_id
  WHERE penalty.id = p_penalty_id
  FOR UPDATE OF penalty, returned;

  IF penalty_row.id IS NULL THEN
    RAISE EXCEPTION 'Denda tidak ditemukan';
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
  FROM public.penalty_payments payment
  WHERE payment.penalty_id = p_penalty_id;

  outstanding := greatest(
    penalty_row.amount - penalty_row.deposit_used - paid_amount,
    0
  );

  IF outstanding <= 0 THEN
    RAISE EXCEPTION 'Denda sudah lunas';
  END IF;

  IF p_amount > outstanding THEN
    RAISE EXCEPTION 'Pembayaran melebihi sisa denda setelah deposit';
  END IF;

  INSERT INTO public.penalty_payments(
    penalty_id,
    payment_date,
    amount,
    payment_method,
    description
  )
  VALUES (
    p_penalty_id,
    p_payment_date,
    p_amount,
    p_payment_method,
    p_description
  )
  RETURNING * INTO new_payment;

  UPDATE public.returns
  SET penalty_payment_status = CASE
    WHEN penalty_row.deposit_used + paid_amount + p_amount >= penalty_row.amount THEN 'Paid'
    ELSE 'Partially Paid'
  END
  WHERE id = penalty_row.return_id;

  RETURN new_payment;
END;
$$;

REVOKE ALL
ON FUNCTION public.record_penalty_payment(bigint,date,numeric,varchar,text)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.record_penalty_payment(bigint,date,numeric,varchar,text)
TO authenticated;

CREATE OR REPLACE FUNCTION public.update_rental_schedule(
  p_rental_id bigint,
  p_return_due_date date,
  p_rental_status varchar
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rental_row public.rentals%ROWTYPE;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff') THEN
    RAISE EXCEPTION 'Role tidak diizinkan mengubah jadwal rental';
  END IF;

  SELECT *
  INTO rental_row
  FROM public.rentals
  WHERE id = p_rental_id
  FOR UPDATE;

  IF rental_row.id IS NULL THEN
    RAISE EXCEPTION 'Rental tidak ditemukan';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.returns
    WHERE rental_id = p_rental_id
  )
    OR coalesce(rental_row.rental_status, rental_row.status) IN ('Cancelled', 'Completed', 'Returned')
  THEN
    RAISE EXCEPTION 'Rental yang selesai atau dibatalkan tidak dapat diubah';
  END IF;

  IF p_return_due_date IS NULL OR p_return_due_date < rental_row.rental_date THEN
    RAISE EXCEPTION 'Tanggal jatuh tempo tidak valid';
  END IF;

  IF p_rental_status NOT IN ('Booked', 'Ongoing') THEN
    RAISE EXCEPTION 'Status rental tidak valid';
  END IF;

  UPDATE public.rentals
  SET return_due_date = p_return_due_date,
      rental_status = p_rental_status,
      status = p_rental_status
  WHERE id = p_rental_id;
END;
$$;

REVOKE ALL
ON FUNCTION public.update_rental_schedule(bigint,date,varchar)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.update_rental_schedule(bigint,date,varchar)
TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_rental(
    p_rental_id bigint,
  p_reason text,
  p_deposit_action varchar,
  p_cancelled_at timestamptz DEFAULT now()
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rental_row public.rentals%ROWTYPE;
  paid_amount numeric;
  detail_row record;
  next_status varchar;
BEGIN
  IF current_app_role() NOT IN ('admin', 'staff', 'accounting') THEN
    RAISE EXCEPTION 'Role tidak diizinkan membatalkan rental';
  END IF;

  SELECT *
  INTO rental_row
  FROM public.rentals
  WHERE id = p_rental_id
  FOR UPDATE;

  IF rental_row.id IS NULL THEN
    RAISE EXCEPTION 'Rental tidak ditemukan';
  END IF;

  IF coalesce(rental_row.rental_status, rental_row.status) IN ('Cancelled', 'Completed', 'Returned') THEN
    RAISE EXCEPTION 'Rental sudah tidak dapat dibatalkan';
  END IF;

  IF nullif(trim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'Alasan pembatalan wajib diisi';
  END IF;

  IF p_deposit_action NOT IN ('REFUND', 'FORFEIT') THEN
    RAISE EXCEPTION 'Penanganan deposit tidak valid';
  END IF;

  FOR detail_row IN
    SELECT
      detail.dress_id,
      detail.dress_variant_id,
      detail.quantity,
      variant.status AS previous_status,
      variant.rented_quantity
    FROM public.rental_details detail
    JOIN public.dress_variants variant
      ON variant.id = detail.dress_variant_id
    WHERE detail.rental_id = p_rental_id
    FOR UPDATE OF variant
  LOOP
    IF detail_row.rented_quantity < detail_row.quantity THEN
      RAISE EXCEPTION 'Jumlah unit disewa tidak konsisten untuk varian %',
        detail_row.dress_variant_id;
    END IF;

    UPDATE public.dress_variants
    SET rented_quantity = rented_quantity - detail_row.quantity,
        available_quantity = available_quantity + detail_row.quantity,
        updated_at = now()
    WHERE id = detail_row.dress_variant_id
    RETURNING status INTO next_status;

    INSERT INTO public.dress_movements(
      dress_id,
      dress_variant_id,
      movement_type,
      reference_id,
      reference_code,
      status_before,
      status_after,
      quantity_delta,
      available_delta,
      rented_delta,
      unavailable_delta,
      description
    )
    VALUES (
      detail_row.dress_id,
      detail_row.dress_variant_id,
      'RENTAL_CANCEL',
      p_rental_id,
      rental_row.rental_code,
      detail_row.previous_status,
      next_status,
      0,
      detail_row.quantity,
      -detail_row.quantity,
      0,
      'Stok ukuran dikembalikan setelah rental dibatalkan'
    );
  END LOOP;

  SELECT coalesce(sum(amount), 0)
  INTO paid_amount
  FROM public.payments
  WHERE rental_id = p_rental_id
    AND payment_type IN ('DP', 'PELUNASAN');

  UPDATE public.rentals
  SET rental_status = 'Cancelled',
      status = 'Cancelled',
      cancellation_reason = p_reason,
      cancelled_at = p_cancelled_at
  WHERE id = p_rental_id;

  IF p_deposit_action = 'REFUND' AND paid_amount > 0 THEN
    INSERT INTO public.payments(
      payment_code,
      rental_id,
      payment_date,
      amount,
      payment_method,
      payment_type,
      notes,
      description
    )
    VALUES (
      public.next_business_code('payment'),
      p_rental_id,
      p_cancelled_at::date,
      paid_amount,
      'Cash',
      'REFUND',
      'Refund pembayaran sewa saat pembatalan',
      'Pengembalian pembayaran sewa'
    );
  END IF;

  PERFORM public.post_two_line_journal(
    public.next_business_code('journal'),
    p_cancelled_at::date,
    'rental_cancel_reversal',
    p_rental_id,
    'Pembalikan pendapatan rental ' || rental_row.rental_code,
    '401',
    '102',
    coalesce(rental_row.total_rental, rental_row.total_amount, 0)
  );

  IF p_deposit_action = 'REFUND' THEN
    IF coalesce(rental_row.deposit_received_amount, 0) > 0 THEN
      PERFORM public.post_two_line_journal(
        public.next_business_code('journal'),
        p_cancelled_at::date,
        'deposit_cancel_refund',
        p_rental_id,
        'Refund deposit ' || rental_row.rental_code,
        '202',
        '101',
        rental_row.deposit_received_amount
      );
    END IF;

    UPDATE public.rentals
    SET payment_status = 'Refunded'
    WHERE id = p_rental_id;
  ELSE
    IF paid_amount > 0 THEN
      PERFORM public.post_two_line_journal(
        public.next_business_code('journal'),
        p_cancelled_at::date,
        'rental_cancel_fee',
        p_rental_id,
        'Biaya pembatalan rental ' || rental_row.rental_code,
        '102',
        '403',
        paid_amount
      );
    END IF;

    IF coalesce(rental_row.deposit_received_amount, 0) > 0 THEN
      PERFORM public.post_two_line_journal(
        public.next_business_code('journal'),
        p_cancelled_at::date,
        'deposit_forfeit',
        p_rental_id,
        'Deposit hangus: ' || p_reason,
        '202',
        '403',
        rental_row.deposit_received_amount
      );
    END IF;
  END IF;
END;
$$;

REVOKE ALL
ON FUNCTION public.cancel_rental(bigint,text,varchar,timestamptz)
FROM PUBLIC, anon;

GRANT EXECUTE
ON FUNCTION public.cancel_rental(bigint,text,varchar,timestamptz)
TO authenticated;

CREATE OR REPLACE FUNCTION public.rental_receivable(p_rental_id bigint)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
  SELECT greatest(
    coalesce(
      (
        SELECT coalesce(total_rental, total_amount)
        FROM public.rentals
        WHERE id = p_rental_id
      ),
      0
    )
    - coalesce(
      (
        SELECT sum(
          CASE
            WHEN payment_type = 'REFUND' THEN -amount
            WHEN payment_type IN ('DP', 'PELUNASAN') THEN amount
            ELSE 0
          END
        )
        FROM public.payments
        WHERE rental_id = p_rental_id
      ),
      0
    ),
    0
  );
$$;

CREATE OR REPLACE VIEW public.v_rental_summary AS
SELECT
  rental.id,
  rental.rental_code,
  customer.name AS customer_name,
  rental.rental_date,
  rental.return_due_date,
  coalesce(rental.total_rental, rental.total_amount) AS total_amount,
  rental.deposit_amount,
  coalesce(
    sum(
      CASE
        WHEN payment.payment_type = 'REFUND' THEN -payment.amount
        WHEN payment.payment_type IN ('DP', 'PELUNASAN') THEN payment.amount
        ELSE 0
      END
    ),
    0
  ) AS paid_amount,
  greatest(
    coalesce(rental.total_rental, rental.total_amount)
    - coalesce(
      sum(
        CASE
          WHEN payment.payment_type = 'REFUND' THEN -payment.amount
          WHEN payment.payment_type IN ('DP', 'PELUNASAN') THEN payment.amount
          ELSE 0
        END
      ),
      0
    ),
    0
  ) AS receivable,
  rental.status
FROM public.rentals rental
JOIN public.customers customer
  ON customer.id = rental.customer_id
LEFT JOIN public.payments payment
  ON payment.rental_id = rental.id
GROUP BY rental.id, customer.name;

REVOKE ALL
ON FUNCTION public.post_two_line_journal(varchar,date,varchar,bigint,varchar,varchar,varchar,numeric)
FROM PUBLIC, anon, authenticated;

REVOKE ALL
ON FUNCTION public.record_new_rental_deposit()
FROM PUBLIC, anon, authenticated;

REVOKE ALL
ON FUNCTION public.set_rental_deposit_received()
FROM PUBLIC, anon, authenticated;

REVOKE INSERT, UPDATE, DELETE
ON public.penalty_payments
FROM authenticated;

GRANT SELECT
ON public.penalty_payments
TO authenticated;

REVOKE INSERT, UPDATE, DELETE
ON public.expense_payments
FROM authenticated;

GRANT SELECT
ON public.expense_payments
TO authenticated;

REVOKE INSERT, UPDATE, DELETE
ON public.rentals, public.payments, public.returns, public.penalties
FROM authenticated;

NOTIFY pgrst, 'reload schema';