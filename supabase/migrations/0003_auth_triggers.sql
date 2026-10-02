-- =============================================================================
-- backend_sdk :: 0003_auth_triggers.sql
-- =============================================================================
-- Create and maintain the application profile row from the auth lifecycle.
--
-- Creating the profile in a trigger rather than from the client means a
-- profile exists for every account, even one created by an admin panel or a
-- seed script, and means a client cannot skip the step.
-- =============================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, display_name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.handle_user_deleted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- The profile row is removed with the account. The cascade on the foreign key
  -- handles this too; the function exists so the intent is explicit and so a
  -- future archive table has an obvious hook point.
  delete from public.users where id = old.id;
  return old;
end;
$$;

drop trigger if exists on_auth_user_deleted on auth.users;
create trigger on_auth_user_deleted
  after delete on auth.users
  for each row execute function public.handle_user_deleted();
