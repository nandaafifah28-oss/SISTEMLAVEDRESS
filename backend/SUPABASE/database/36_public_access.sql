-- This migration grants anonymous users unrestricted access to application data.
-- Do not apply to a deployment containing private or production customer data.

GRANT USAGE ON SCHEMA public TO anon;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO anon;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon;

DO $$
DECLARE
  table_record record;
BEGIN
  FOR table_record IN
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.%I DISABLE ROW LEVEL SECURITY',
      table_record.tablename
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.current_app_role()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 'admin'::text;
$$;

DROP POLICY IF EXISTS dress_photos_anon_read ON storage.objects;

CREATE POLICY dress_photos_anon_read
ON storage.objects
FOR SELECT
TO anon
USING (bucket_id = 'dress-photos');

DROP POLICY IF EXISTS dress_photos_anon_insert ON storage.objects;

CREATE POLICY dress_photos_anon_insert
ON storage.objects
FOR INSERT
TO anon
WITH CHECK (bucket_id = 'dress-photos');

DROP POLICY IF EXISTS dress_photos_anon_update ON storage.objects;

CREATE POLICY dress_photos_anon_update
ON storage.objects
FOR UPDATE
TO anon
USING (bucket_id = 'dress-photos')
WITH CHECK (bucket_id = 'dress-photos');

DROP POLICY IF EXISTS dress_photos_anon_delete ON storage.objects;

CREATE POLICY dress_photos_anon_delete
ON storage.objects
FOR DELETE
TO anon
USING (bucket_id = 'dress-photos');