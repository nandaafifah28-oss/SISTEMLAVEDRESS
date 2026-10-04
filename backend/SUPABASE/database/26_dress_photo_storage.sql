-- Public display bucket for dress model photos; uploads require an active
-- operational user and are isolated under that user's folder.

INSERT INTO storage.buckets(id, name, public)
VALUES ('dress-photos', 'dress-photos', true)
ON CONFLICT (id) DO UPDATE
SET public = true;

DROP POLICY IF EXISTS dress_photos_authenticated_read ON storage.objects;

CREATE POLICY dress_photos_authenticated_read
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'dress-photos');

DROP POLICY IF EXISTS dress_photos_authenticated_insert ON storage.objects;

CREATE POLICY dress_photos_authenticated_insert
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'dress-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND current_app_role() IN ('admin','staff')
);

DROP POLICY IF EXISTS dress_photos_authenticated_delete ON storage.objects;

CREATE POLICY dress_photos_authenticated_delete
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'dress-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
  AND current_app_role() IN ('admin','staff')
);