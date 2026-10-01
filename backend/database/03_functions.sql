create or replace function journal_is_balanced(p_journal_id bigint)
returns boolean
language sql
as $$
  select
    coalesce(
      (
        select sum(debit)
        from journal_details
        where journal_id=p_journal_id
      ),
      0
    )=
    coalesce(
      (
        select sum(credit)
        from journal_details
        where journal_id=p_journal_id
      ),
      0
    )
$$;

create or replace function rental_receivable(p_rental_id bigint)
returns numeric
language sql
as $$
  select
    greatest(
      coalesce(
        (
          select total_amount
          from rentals
          where id=p_rental_id
        ),
        0
      )-
      coalesce(
        (
          select sum(amount)
          from payments
          where rental_id=p_rental_id
        ),
        0
      ),
      0
    )
$$;