-- =============================================================================
-- backend_sdk :: 0004_column_privileges.sql
-- =============================================================================
-- Column-level privileges.
--
-- RLS decides which ROWS a caller may touch. It cannot restrict which COLUMNS
-- they may write: a policy that allows `UPDATE` on a user's own row would also
-- allow `role = 'admin'`. This migration closes that gap by granting UPDATE per
-- column.
--
-- This is the difference between "the client hides the admin toggle" and "the
-- database refuses the write". Only the second one is security.
-- =============================================================================

-- The default Supabase grants give `authenticated` blanket table privileges.
-- Revoke first, then re-grant narrowly.
revoke all on public.users from anon, authenticated;
revoke all on public.products from anon, authenticated;

-- --- public.users ------------------------------------------------------------
grant select on public.users to authenticated;
grant update (display_name, email, avatar_path) on public.users to authenticated;
-- No INSERT or DELETE: the trigger owns the row lifecycle.
-- No UPDATE on `role` or `is_active`: administrative state is server-side only.

-- --- public.products ---------------------------------------------------------
grant select on public.products to anon, authenticated;
grant insert on public.products to authenticated;
grant update (name, price, stock, category_id, is_active, deleted_at)
  on public.products to authenticated;
-- No DELETE for clients. Soft-delete via `deleted_at` keeps the audit trail that
-- the RLS policies and any referential integrity depend on.

-- =============================================================================
-- Promotion to admin
-- =============================================================================
-- Never from a client. Either:
--   * Supabase dashboard -> Authentication -> Users -> App Metadata ->
--     {"role": "admin"}, which is what `public.is_admin()` reads, or
--   * a server-side job running with the service_role key:
--
--       update auth.users
--          set raw_app_meta_data = raw_app_meta_data || '{"role":"admin"}'
--        where id = '<user-uuid>';
--
-- Because `is_admin()` reads `app_metadata` rather than `user_metadata`, a user
-- cannot grant themselves the role by calling
-- `BackendSdk.instance.auth.updateUserMetadata(...)`.
