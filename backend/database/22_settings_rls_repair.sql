-- Restore settings singleton rows and role-based RLS policies.
-- Run after 21_capital_role_access.sql.

BEGIN;

INSERT INTO business_settings(id)
VALUES (true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO accounting_settings(id)
VALUES (true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO system_preferences(id)
VALUES (true)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE business_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE accounting_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_preferences ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS business_settings_read ON business_settings;
DROP POLICY IF EXISTS business_settings_admin_write ON business_settings;

CREATE POLICY business_settings_read
ON business_settings
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY business_settings_admin_write
ON business_settings
FOR ALL
TO authenticated
USING (current_app_role() = 'admin')
WITH CHECK (current_app_role() = 'admin');

DROP POLICY IF EXISTS accounting_settings_admin ON accounting_settings;

CREATE POLICY accounting_settings_admin
ON accounting_settings
FOR ALL
TO authenticated
USING (current_app_role() IN ('admin','accounting'))
WITH CHECK (current_app_role() IN ('admin','accounting'));

DROP POLICY IF EXISTS system_preferences_user ON system_preferences;
DROP POLICY IF EXISTS system_preferences_admin ON system_preferences;

CREATE POLICY system_preferences_user
ON system_preferences
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY system_preferences_admin
ON system_preferences
FOR ALL
TO authenticated
USING (current_app_role() = 'admin')
WITH CHECK (current_app_role() = 'admin');

COMMIT;