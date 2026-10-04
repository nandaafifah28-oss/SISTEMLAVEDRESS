-- Prepare an explicit, reviewed mapping for legacy duplicate dress models.
-- Run this first, inspect the candidate query below, then insert only confirmed
-- source_dress_id -> target_dress_id pairs before running migration 24.

CREATE TABLE IF NOT EXISTS public.dress_model_merge_map (
  source_dress_id bigint PRIMARY KEY REFERENCES public.dresses(id) ON DELETE RESTRICT,
  target_dress_id bigint NOT NULL REFERENCES public.dresses(id) ON DELETE RESTRICT,
  reason text NOT NULL,
  mapped_by uuid REFERENCES auth.users(id),
  mapped_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dress_model_merge_map_not_self CHECK (source_dress_id <> target_dress_id)
);

ALTER TABLE public.dress_model_merge_map ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.dress_model_merge_map FROM PUBLIC, anon;

GRANT SELECT, INSERT, UPDATE, DELETE
ON public.dress_model_merge_map
TO authenticated;

DROP POLICY IF EXISTS dress_model_merge_map_admin ON public.dress_model_merge_map;

CREATE POLICY dress_model_merge_map_admin
ON public.dress_model_merge_map
FOR ALL
TO authenticated
USING (current_app_role() = 'admin')
WITH CHECK (current_app_role() = 'admin');

-- Suggested review query. Matching names are candidates only, never proof of
-- identity: confirm model, category, color, photo, and legacy transactions.
--
-- SELECT
--   a.id AS source_dress_id,
--   a.dress_code AS source_code,
--   a.name,
--   a.size AS source_size,
--   b.id AS target_dress_id,
--   b.dress_code AS target_code,
--   b.size AS target_size
-- FROM public.dresses a
-- JOIN public.dresses b
--   ON lower(trim(a.name)) = lower(trim(b.name))
--   AND a.id <> b.id
-- ORDER BY lower(trim(a.name)), a.id, b.id;
--
-- Find exact active model-identity duplicates that must be mapped before 24:
-- SELECT
--   lower(trim(name)) AS model_name,
--   category_id,
--   lower(trim(coalesce(color,''))) AS model_color,
--   array_agg(id ORDER BY id) AS dress_ids,
--   count(*) AS row_count
-- FROM public.dresses
-- WHERE is_active
-- GROUP BY
--   lower(trim(name)),
--   category_id,
--   lower(trim(coalesce(color,'')))
-- HAVING count(*) > 1;
--
-- Review sizes, active/status counts, and historical purchase quantities:
-- SELECT
--   d.id,
--   d.dress_code,
--   d.name,
--   d.size,
--   d.status,
--   d.is_active,
--   count(pd.id) AS purchase_lines,
--   coalesce(sum(pd.quantity), 0) AS historical_purchase_qty
-- FROM public.dresses d
-- LEFT JOIN public.purchase_details pd ON pd.dress_id = d.id
-- GROUP BY d.id
-- ORDER BY d.dress_code;