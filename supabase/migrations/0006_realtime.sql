-- =============================================================================
-- backend_sdk :: 0006_realtime.sql
-- =============================================================================
-- Realtime publication.
--
-- A table only emits change events once it is in the `supabase_realtime`
-- publication. Without this, `BackendSdk.instance.realtime.watch<Product>(...)`
-- connects successfully and then silently receives nothing - the hardest kind
-- of realtime bug to diagnose, because there is no error.
-- =============================================================================

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'products'
  ) then
    alter publication supabase_realtime add table public.products;
  end if;
end
$$;

-- `public.users` is deliberately NOT added. A publication on `users` would
-- broadcast email addresses and profile changes to every connected client that
-- holds a matching filter, which is more than a client needs. Subscribe to your
-- own user row through `auth.onAuthStateChange`, or add the table here only after
-- you have audited what each role may observe.
