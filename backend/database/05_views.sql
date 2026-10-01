create or replace view v_rental_summary as
select
  r.id,
  r.rental_code,
  c.name customer_name,
  r.rental_date,
  r.return_due_date,
  r.total_amount,
  r.deposit_amount,
  coalesce(sum(p.amount),0) paid_amount,
  greatest(
    r.total_amount-coalesce(sum(p.amount),0),
    0
  ) receivable,
  r.status
from rentals r
join customers c on c.id=r.customer_id
left join payments p on p.rental_id=r.id
group by r.id,c.name;