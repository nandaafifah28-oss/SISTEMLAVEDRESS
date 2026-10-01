insert into dress_categories(category_name,description)
values
  ('Evening Dress','Dress formal'),
  ('Party Dress','Dress pesta'),
  ('Wedding Guest','Dress tamu pernikahan'),
  ('Graduation','Dress wisuda')
on conflict do nothing;

insert into expense_categories(category_name)
values
  ('Laundry'),
  ('Repair'),
  ('Electricity'),
  ('Internet'),
  ('Promotion'),
  ('Transportation'),
  ('Rent'),
  ('Packaging'),
  ('Other')
on conflict do nothing;

insert into accounts(account_code,account_name,account_type)
values
  ('101','Kas','Asset'),
  ('102','Piutang Usaha','Asset'),
  ('103','Persediaan Dress','Asset'),
  ('104','Peralatan','Asset'),
  ('201','Utang Usaha','Liability'),
  ('202','Deposit Pelanggan','Liability'),
  ('301','Modal Pemilik','Equity'),
  ('401','Pendapatan Sewa','Revenue'),
  ('402','Pendapatan Denda','Revenue'),
  ('501','Beban Laundry','Expense'),
  ('502','Beban Repair','Expense'),
  ('503','Beban Listrik','Expense'),
  ('504','Beban Internet','Expense'),
  ('505','Beban Promosi','Expense'),
  ('506','Beban Transportasi','Expense'),
  ('507','Beban Sewa Tempat','Expense'),
  ('508','Beban Lain-lain','Expense')
on conflict do nothing;

insert into customers(customer_code,name,phone,email,address)
values
  ('CUS-001','Customer Demo','081234567890','customer@example.com','Semarang')
on conflict do nothing;

insert into suppliers(supplier_code,name,phone,email,address)
values
  ('SUP-001','Supplier Demo','081234567891','supplier@example.com','Semarang')
on conflict do nothing;

insert into dresses(
  dress_code,
  name,
  category_id,
  size,
  color,
  purchase_price,
  rental_price,
  condition,
  status,
  supplier_id
)
select
  'DR-001',
  'Aurora Gown',
  id,
  'M',
  'Navy',
  2500000,
  350000,
  'Good',
  'Available',
  (select id from suppliers where supplier_code='SUP-001')
from dress_categories
where category_name='Evening Dress'
  and not exists(
    select 1
    from dresses
    where dress_code='DR-001'
  );

insert into dresses(
  dress_code,
  name,
  category_id,
  size,
  color,
  purchase_price,
  rental_price,
  condition,
  status,
  supplier_id
)
select
  'DR-002',
  'Emerald Party Dress',
  id,
  'L',
  'Emerald',
  1800000,
  300000,
  'Good',
  'Available',
  (select id from suppliers where supplier_code='SUP-001')
from dress_categories
where category_name='Party Dress'
  and not exists(
    select 1
    from dresses
    where dress_code='DR-002'
  );