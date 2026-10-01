create or replace function trg_payment_status()
returns trigger
language plpgsql
as $$
declare
  total numeric;
  paid numeric;
begin
  select total_amount
  into total
  from rentals
  where id=new.rental_id;

  select coalesce(sum(amount),0)
  into paid
  from payments
  where rental_id=new.rental_id;

  if paid>=total then
    update rentals
    set status='Paid'
    where id=new.rental_id;
  else
    update rentals
    set status='Partially Paid'
    where id=new.rental_id;
  end if;

  return new;
end;
$$;

drop trigger if exists after_payment_status on payments;

create trigger after_payment_status
after insert on payments
for each row
execute function trg_payment_status();

create or replace function trg_complete_rental()
returns trigger
language plpgsql
as $$
begin
  update rentals
  set status='Completed'
  where id=new.rental_id;

  return new;
end;
$$;

drop trigger if exists after_return_complete on returns;

create trigger after_return_complete
after insert on returns
for each row
execute function trg_complete_rental();