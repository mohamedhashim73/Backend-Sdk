-- =============================================================================
-- backend_sdk :: 0005_storage_buckets.sql
-- =============================================================================
-- Storage buckets matching the `StorageBucket` enum in backend_sdk.
--
-- Every bucket is PRIVATE (`public = false`). Private content must be read
-- through `BackendSdk.instance.storage.createSignedUrl(...)`, which returns a
-- short-lived URL; a public bucket turns its object keys into guessable,
-- indefinitely valid URLs.
--
-- The bucket identifiers here must match the mapping in
-- `lib/src/providers/supabase/supabase_storage_backend.dart`.
-- =============================================================================

-- General purpose user content.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'general', 'general', false, 10485760,
  array['image/png', 'image/jpeg', 'image/webp', 'application/pdf', 'text/plain']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Profile images.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars', 'avatars', false, 2097152,
  array['image/png', 'image/jpeg', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Product media.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'products', 'products', false, 10485760,
  array['image/png', 'image/jpeg', 'image/webp', 'video/mp4']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Private documents.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'documents', 'documents', false, 10485760,
  array['application/pdf', 'text/plain', 'text/csv',
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- =============================================================================
-- Storage policies
-- =============================================================================
-- `storage.objects` has its own RLS, separate from the table policies above.
-- The rule applied throughout: **the first path segment is the owning user id**,
-- so a signed-in caller can only ever reach their own folder.
--
-- backend_sdk validates that a path contains no "." or ".." segment before the
-- request is made, so a client cannot use path traversal to escape its prefix.
-- The policies below are the second line of defence; neither is sufficient alone.
-- =============================================================================

-- Helper: the first segment of an object name, compared to the caller.
create or replace function public.storage_owner(object_name text)
returns text
language sql
immutable
as $$
  select split_part(object_name, '/', 1);
$$;

-- Owner-based: a user reads their own folder in any bucket.
drop policy if exists storage_select_own on storage.objects;
create policy storage_select_own
  on storage.objects
  for select
  to authenticated
  using (public.storage_owner(name) = auth.uid()::text);

-- Owner-based: a user writes their own folder.
drop policy if exists storage_insert_own on storage.objects;
create policy storage_insert_own
  on storage.objects
  for insert
  to authenticated
  with check (public.storage_owner(name) = auth.uid()::text);

drop policy if exists storage_update_own on storage.objects;
create policy storage_update_own
  on storage.objects
  for update
  to authenticated
  using (public.storage_owner(name) = auth.uid()::text)
  with check (public.storage_owner(name) = auth.uid()::text);

drop policy if exists storage_delete_own on storage.objects;
create policy storage_delete_own
  on storage.objects
  for delete
  to authenticated
  using (public.storage_owner(name) = auth.uid()::text);

-- Admin: full access to every bucket, for operator tooling and moderation.
drop policy if exists storage_admin_all on storage.objects;
create policy storage_admin_all
  on storage.objects
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Anonymous access is deliberately absent: no bucket is public, so there is
-- nothing for an unauthenticated caller to read.
--
-- Because `public = false` on every bucket, `getPublicUrl` will produce a URL
-- that returns 403. Use `createSignedUrl` for private content; the SDK's
-- `SignedFileUrl.toString()` deliberately omits the URL so it never lands in a
-- log.
