-- Recreate v_dress_inventory so sampled column expressions do not reference
-- CTE aliases such as counts without a FROM clause.
-- Run after 34_unit_return_inventory_flows.sql.

BEGIN;

DROP VIEW IF EXISTS public.v_dress_inventory;

CREATE VIEW public.v_dress_inventory WITH (security_invoker = true) AS
SELECT
  dress_variant_id,
  dress_id,
  dress_code,
  name,
  category_id,
  category_name,
  color,
  purchase_price,
  rental_price,
  supplier_id,
  supplier_name,
  photo_url,
  description,
  size,
  quantity,
  available_quantity,
  rented_quantity,
  unavailable_quantity,
  condition,
  status,
  laundry_quantity,
  repair_quantity,
  not_available_quantity,
  unclassified_quantity
FROM (
  SELECT
    variant.id AS dress_variant_id,
    model.id AS dress_id,
    model.dress_code,
    model.name,
    model.category_id,
    category.category_name,
    variant.color,
    model.purchase_price,
    model.rental_price,
    model.supplier_id,
    supplier.name AS supplier_name,
    model.photo_url,
    model.description,
    variant.size,
    coalesce(unit_counts.quantity, 0) AS quantity,
    coalesce(unit_counts.available_quantity, 0) AS available_quantity,
    coalesce(unit_counts.rented_quantity, 0) AS rented_quantity,
    coalesce(unit_counts.unavailable_quantity, 0) AS unavailable_quantity,
    coalesce(unit_counts.condition, variant.condition)::varchar(30) AS condition,
    CASE
      WHEN coalesce(unit_counts.unclassified_count, 0) > 0 THEN 'Unclassified'
      WHEN coalesce(unit_counts.available_count, 0) > 0
        AND coalesce(unit_counts.unavailable_count, 0) + coalesce(unit_counts.rented_count, 0) > 0
      THEN 'Mixed'
      WHEN coalesce(unit_counts.available_count, 0) > 0 THEN 'Available'
      WHEN coalesce(unit_counts.rented_count, 0) > 0
        AND coalesce(unit_counts.unavailable_count, 0) > 0
      THEN 'Mixed'
      WHEN coalesce(unit_counts.rented_count, 0) > 0 THEN 'Rented'
      WHEN coalesce(unit_counts.laundry_quantity, 0) > 0 THEN 'Laundry'
      WHEN coalesce(unit_counts.repair_quantity, 0) > 0 THEN 'Repair'
      ELSE 'Not Available'
    END::varchar(30) AS status,
    coalesce(unit_counts.laundry_quantity, 0) AS laundry_quantity,
    coalesce(unit_counts.repair_quantity, 0) AS repair_quantity,
    coalesce(unit_counts.not_available_quantity, 0) AS not_available_quantity,
    coalesce(unit_counts.unclassified_quantity, 0) AS unclassified_quantity
  FROM public.dress_variants variant
  JOIN public.dresses model
    ON model.id = variant.dress_id
  LEFT JOIN public.dress_categories category
    ON category.id = model.category_id
  LEFT JOIN public.suppliers supplier
    ON supplier.id = model.supplier_id
  LEFT JOIN (
    SELECT
      unit.variant_id,
      count(*)::integer AS quantity,
      count(*) FILTER (
        WHERE unit.status = 'Available'
      )::integer AS available_quantity,
      count(*) FILTER (
        WHERE unit.status = 'Rented'
      )::integer AS rented_quantity,
      count(*) FILTER (
        WHERE unit.status IN ('Laundry','Repair','Not Available','Unclassified')
      )::integer AS unavailable_quantity,
      count(*) FILTER (
        WHERE unit.status = 'Laundry'
      )::integer AS laundry_quantity,
      count(*) FILTER (
        WHERE unit.status = 'Repair'
      )::integer AS repair_quantity,
      count(*) FILTER (
        WHERE unit.status = 'Not Available'
      )::integer AS not_available_quantity,
      count(*) FILTER (
        WHERE unit.status = 'Unclassified'
      )::integer AS unclassified_quantity,
      CASE
        WHEN count(DISTINCT unit.condition) = 1 THEN min(unit.condition)
        ELSE 'Mixed'
      END AS condition,
      count(*) FILTER (
        WHERE unit.status = 'Available'
      ) AS available_count,
      count(*) FILTER (
        WHERE unit.status = 'Rented'
      ) AS rented_count,
      count(*) FILTER (
        WHERE unit.status IN ('Laundry','Repair','Not Available','Unclassified')
      ) AS unavailable_count,
      count(*) FILTER (
        WHERE unit.status = 'Unclassified'
      ) AS unclassified_count
    FROM public.dress_units unit
    GROUP BY unit.variant_id
  ) unit_counts
    ON unit_counts.variant_id = variant.id
  WHERE model.is_active
) inventory;

REVOKE ALL
ON public.v_dress_inventory
FROM PUBLIC, anon;

GRANT SELECT
ON public.v_dress_inventory
TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;