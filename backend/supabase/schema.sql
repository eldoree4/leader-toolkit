create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text not null default '',
  role text not null default 'supervisor'
    check (role in ('leader', 'supervisor')),
  created_at timestamptz not null default now()
);

create table if not exists public.operators (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  line_name text not null,
  main_process text not null,
  skills jsonb not null default '[]'::jsonb,
  created_by uuid not null default auth.uid()
    references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.production_entries (
  id uuid primary key default gen_random_uuid(),
  style_name text not null,
  process text not null,
  line_name text not null,
  target integer not null check (target > 0),
  actual integer not null default 0 check (actual >= 0),
  defects integer not null default 0 check (defects >= 0),
  downtime_minutes integer not null default 0 check (downtime_minutes >= 0),
  recorded_by uuid not null default auth.uid()
    references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select role
  from public.profiles
  where id = auth.uid();
$$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists operators_set_updated_at on public.operators;
create trigger operators_set_updated_at
before update on public.operators
for each row execute function public.set_updated_at();

drop trigger if exists production_set_updated_at on public.production_entries;
create trigger production_set_updated_at
before update on public.production_entries
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.operators enable row level security;
alter table public.production_entries enable row level security;

grant select on public.profiles to authenticated;
grant select, insert, update, delete on public.operators to authenticated;
grant select, insert, update, delete on public.production_entries to authenticated;

drop policy if exists "profiles read own" on public.profiles;
create policy "profiles read own"
on public.profiles
for select to authenticated
using (id = auth.uid());

drop policy if exists "operators read authenticated" on public.operators;
create policy "operators read authenticated"
on public.operators
for select to authenticated
using (true);

drop policy if exists "leader insert operators" on public.operators;
create policy "leader insert operators"
on public.operators
for insert to authenticated
with check (public.current_app_role() = 'leader');

drop policy if exists "leader update operators" on public.operators;
create policy "leader update operators"
on public.operators
for update to authenticated
using (public.current_app_role() = 'leader')
with check (public.current_app_role() = 'leader');

drop policy if exists "leader delete operators" on public.operators;
create policy "leader delete operators"
on public.operators
for delete to authenticated
using (public.current_app_role() = 'leader');

drop policy if exists "production read authenticated" on public.production_entries;
create policy "production read authenticated"
on public.production_entries
for select to authenticated
using (true);

drop policy if exists "leader insert production" on public.production_entries;
create policy "leader insert production"
on public.production_entries
for insert to authenticated
with check (public.current_app_role() = 'leader');

drop policy if exists "leader update production" on public.production_entries;
create policy "leader update production"
on public.production_entries
for update to authenticated
using (public.current_app_role() = 'leader')
with check (public.current_app_role() = 'leader');

drop policy if exists "leader delete production" on public.production_entries;
create policy "leader delete production"
on public.production_entries
for delete to authenticated
using (public.current_app_role() = 'leader');

-- Aktifkan realtime untuk tabel yang dipakai aplikasi.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'operators'
  ) then
    alter publication supabase_realtime add table public.operators;
  end if;

  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'production_entries'
  ) then
    alter publication supabase_realtime add table public.production_entries;
  end if;
end
$$;

