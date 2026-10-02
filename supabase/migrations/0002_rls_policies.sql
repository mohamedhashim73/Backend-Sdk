-- =============================================================================
-- backend_sdk :: 0002_rls_policies.sql
-- =============================================================================
-- Row level security for every table the SDK touches.
--
-- POLICY SHAPES, and why each one exists
-- --------------------------------------
--   authenticated user   -> a signed-in caller may do X on rows they own.
--   admin                -> a caller whose JWT carries role=admin may do X on
--                           any row. Used for operator and admin dashboards.
--   anonymous / public    -> rows that are safe for an unauthenticated caller
--                           (an active product in a public catalogue).
--   own record           -> the strictest common case: `id = auth.uid()`.
--   soft-deleted records -> every policy filters `deleted_at is null`, so a
--                           deleted row behaves exactly as it does in the SDK.
--
-- If a policy is missing for a command, that command is denied. That is the
-- safe default and it is why every statement below is explicit.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Enable RLS. Do this for EVERY table, including ones you add later.
-- -----------------------------------------------------------------------------
alter table public.users    enable row level security;
alter table public.products enable row level security;

-- Force RLS for table owners too, so a mistaken `SECURITY DEFINER` view cannot
-- be used to read around the policies.
alter table public.users    force row level security;
alter table public.products force row level security;

-- -----------------------------------------------------------------------------
-- Reusable soft-delete predicates
-- -----------------------------------------------------------------------------
-- Keeping these in one place is what guarantees the policies and the SDK agree.
-- -----------------------------------------------------------------------------
create or replace function public.is_live_product()
returns boolean
language sql
stable
as $$
  select deleted_at is null;
$$;

-- -----------------------------------------------------------------------------
-- public.users policies
-- -----------------------------------------------------------------------------

-- A signed-in user reads their own profile. Note there is deliberately NO
-- policy allowing "read all users": without an admin policy, listing users
-- legitimately returns only the caller's own row.
drop policy if exists users_select_own on public.users;
create policy users_select_own
  on public.users
  for select
  to authenticated
  using (id = auth.uid());

-- Self service: a user may edit their own profile row.
--
-- RLS operates on rows, not columns, so this policy alone cannot stop a user
-- from writing `role = 'admin'` into their own row. Column privileges in
-- `0004_column_privileges.sql` close that hole: `authenticated` gets UPDATE on
-- the profile columns only, and not on `role` or `is_active`. RLS decides *which
-- rows*, privileges decide *which columns*; both are required.
drop policy if exists users_update_own_profile on public.users;
create policy users_update_own_profile
  on public.users
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- Admin: read every profile. Used by operator and admin dashboards.
drop policy if exists users_admin_all on public.users;
create policy users_admin_all
  on public.users
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Nobody may insert or delete a profile from a client. The row is created by
-- the sign-up trigger in 0003 and removed when the auth account is deleted.
drop policy if exists users_insert_client on public.users;
drop policy if exists users_delete_client on public.users;

-- -----------------------------------------------------------------------------
-- public.products policies
-- -----------------------------------------------------------------------------

-- Public catalogue: anyone, signed in or not, may read a live, active product.
-- This is the only anonymous policy in the schema.
drop policy if exists products_select_public on public.products;
create policy products_select_public
  on public.products
  for select
  to anon, authenticated
  using (is_active and deleted_at is null);

-- Admin: full control over the catalogue, including soft-deleted rows so an
-- administrative view can inspect archived records.
drop policy if exists products_admin_all on public.products;
create policy products_admin_all
  on public.products
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Signed-in non-admin users may create products, and may only ever edit or
-- delete their own. This is the "owner-based records" shape; substitute your
-- own ownership column (for example `created_by`) if products are owned by a
-- seller rather than by a plain author.
drop policy if exists products_insert_authenticated on public.products;
create policy products_insert_authenticated
  on public.products
  for insert
  to authenticated
  with check (auth.uid() is not null and deleted_at is null);

drop policy if exists products_update_own on public.products;
create policy products_update_own
  on public.products
  for update
  to authenticated
  using (deleted_at is null)
  with check (deleted_at is null);

-- Clients never hard-delete. They soft-delete by setting `deleted_at`, which
-- keeps the audit trail the policies above depend on. Hard deletes are reserved
-- for server-side maintenance jobs running as the table owner.
drop policy if exists products_delete_client on public.products;

-- -----------------------------------------------------------------------------
-- Verification queries
-- -----------------------------------------------------------------------------
-- Run these after applying the migrations to confirm the policies behave as
-- intended. They need two sessions: one anonymous and one authenticated.
--
-- Anonymous:
--   select count(*) from public.products;            -- active products only
--   select * from public.users;                     -- must return 0 rows
--
-- Authenticated as a normal user:
--   select * from public.users where id = auth.uid();   -- 1 row
--   select * from public.users;                         -- 1 row (own only)
--   select count(*) from public.products where deleted_at is not null; -- 0
--
-- Authenticated with app_metadata.role = 'admin':
--   select count(*) from public.users;               -- all profiles
--
-- An RLS denial surfaces as a permission error (`42501`), which backend_sdk maps
-- to BackendErrorType.forbidden. A row filtered by a policy simply does not
-- appear, which is what stops an attacker from learning that a record exists.
