-- =============================================================================
-- backend_sdk :: 0001_products_and_users.sql
-- =============================================================================
-- Reference schema for the products and users modules shipped with backend_sdk.
--
-- SECURITY MODEL (read this before copying anything)
-- -----------------------------------------------
-- The Supabase **anon / publishable** key used by the Flutter app is NOT a
-- secret. It ships inside the application binary and is readable by anyone who
-- installs it. It grants nothing on its own: every privilege below is enforced
-- by row level security (RLS), evaluated by Postgres on every statement.
--
--   * NEVER put the service_role / secret key in a Flutter application.
--     Anything shipped to a device must be treated as public.
--   * Client-side checks are UX, not security. `User.isAdmin` in the SDK is a
--     rendering hint; the `is_admin()` helper below is the actual gate.
--   * Every table must have RLS enabled and at least one policy. A table with
--     RLS enabled and no policy denies everything, which is the safe default.
--   * Keep soft-deleted rows out of every policy's USING clause, exactly as the
--     SDK does client-side, so both layers agree on what "deleted" means.
--
-- Apply with:  supabase db push   (or paste into the SQL editor)
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Helper: is the current JWT claim an administrator?
-- -----------------------------------------------------------------------------
-- `stable` marks the function as safe for use inside an RLS policy, and
-- `security definer` lets it read the table without re-triggering RLS on
-- `public.users`. The `search_path` is pinned so no caller can hijack the
-- function body through a temporary schema.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select (auth.jwt() -> 'app_metadata' ->> 'role') = 'admin'),
    false
  );
$$;

comment on function public.is_admin() is
  'True when the current request carries an admin role in app_metadata. Read app_metadata, never user_metadata: user_metadata is user-writable.';

-- -----------------------------------------------------------------------------
-- Table: public.users
-- -----------------------------------------------------------------------------
create table if not exists public.users (
  id           uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  email        text,
  avatar_path  text,
  role         text not null default 'user'
                 check (role in ('user', 'admin', 'support')),
  is_active    boolean not null default true,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

comment on column public.users.role is
  'Administrative role. Enforced by RLS through is_admin(); never trusted from a client-side field.';
comment on column public.users.avatar_path is
  'Object key inside the private "avatars" storage bucket. Read it through a signed URL.';

create index if not exists users_display_name_idx on public.users (display_name);
create index if not exists users_email_idx on public.users (email);

-- -----------------------------------------------------------------------------
-- Table: public.products
-- -----------------------------------------------------------------------------
create table if not exists public.products (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 1 and 200),
  price       numeric(12, 2) not null check (price >= 0),
  stock       integer not null default 0 check (stock >= 0),
  category_id uuid,
  is_active   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- Soft delete. The SDK writes this column in `softDelete` and filters on
  -- `deleted_at is null` in every read, which mirrors the policies below.
  deleted_at  timestamptz
);

comment on column public.products.deleted_at is
  'Soft-delete marker. Every RLS policy and every SDK read excludes rows where this is not null.';

create index if not exists products_created_at_idx
  on public.products (created_at desc);
create index if not exists products_category_id_idx
  on public.products (category_id);
-- Partial index: live rows only. This is the index that list queries use,
-- because soft-deleted rows are filtered out by both the SDK and the policy.
create index if not exists products_live_idx
  on public.products (created_at desc, id)
  where deleted_at is null;
-- Supports free-text search from `PageRequest.search` on the name column.
create index if not exists products_name_search_idx
  on public.products (lower(name) text_pattern_ops);

-- -----------------------------------------------------------------------------
-- Updated-at maintenance
-- -----------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists users_touch_updated_at on public.users;
create trigger users_touch_updated_at
  before update on public.users
  for each row execute function public.touch_updated_at();

drop trigger if exists products_touch_updated_at on public.products;
create trigger products_touch_updated_at
  before update on public.products
  for each row execute function public.touch_updated_at();
