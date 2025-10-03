-- EtBook Supabase schema (v2) aligning with mobile app expectations
-- Tables: orgs, org_members, books, entries, categories, tags, org_invites
-- RPCs: push_book, push_entry, push_category, push_tag, create_org_invite, accept_org_invite

-- Extensions
create extension if not exists pgcrypto;

-- Organizations
create table if not exists public.orgs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  owner_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Compatibility: ensure timestamp columns exist if the legacy table lacked them
alter table public.orgs add column if not exists created_at timestamptz not null default now();
alter table public.orgs add column if not exists updated_at timestamptz not null default now();

-- If orgs existed previously without owner_id, add and backfill
alter table public.orgs add column if not exists owner_id uuid;
-- Members
create table if not exists public.org_members (
  org_id uuid not null references public.orgs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','member','viewer')),
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);

-- Best-effort backfill owner_id from existing owner membership rows (ensure table exists first)
update public.orgs o
set owner_id = m.user_id
from public.org_members m
where m.org_id = o.id and m.role = 'owner' and o.owner_id is null;

-- Legacy compatibility & recursion fix ---------------------------------------------------------
-- Some earlier versions used a table named 'memberships' which acquired a recursive RLS policy
-- (policy queried the same table), producing: 42P17 infinite recursion detected.
-- The current canonical table name is 'org_members'. This block:
-- 1. Renames legacy table if it exists and new table absent.
-- 2. Drops any old recursive policies that may still be attached to 'memberships'.
-- 3. (Optional) Creates a view 'memberships' for backward compatibility without RLS.
-- Idempotent and safe to run multiple times.

do $$
begin
  -- If legacy table exists and new canonical table does NOT, rename it.
  if to_regclass('public.memberships') is not null and to_regclass('public.org_members') is null then
    execute 'alter table public.memberships rename to org_members';
  end if;
exception when others then
  -- Swallow errors to avoid migration abort; investigation can look at server logs.
  raise notice 'Legacy memberships rename skipped: %', sqlerrm;
end $$;

-- Drop any lingering policies directly on a still-existing legacy 'memberships' table (if both exist).
do $$ declare r record; begin
  if to_regclass('public.memberships') is not null then
    for r in (
      select polname from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = 'memberships'
    ) loop
      execute format('drop policy if exists %I on public.memberships', r.polname);
    end loop;
  end if;
end $$;

-- Provide a simple compatibility view if legacy name is still referenced by application code.
do $$
begin
  if to_regclass('public.memberships') is null then
    execute 'create or replace view public.memberships as select org_id, user_id, role, created_at from public.org_members';
  end if;
end $$;

-- NOTE: Do NOT add policies on the compatibility view; it will inherit policies from base table.
-- End legacy compatibility ----------------------------------------------------------------------

-- Books (org or personal)
create table if not exists public.books (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references public.orgs(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  name text not null,
  color text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  constraint books_scope_xor check ((org_id is not null and user_id is null) or (org_id is null and user_id is not null))
);
-- Compatibility: ensure timestamp columns exist if the legacy table lacked them
alter table public.books add column if not exists created_at timestamptz not null default now();
alter table public.books add column if not exists updated_at timestamptz not null default now();
alter table public.books add column if not exists deleted_at timestamptz;
-- Compatibility: ensure legacy organization column is renamed and scoped FK columns exist
do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'books'
      and column_name = 'organization_id'
  ) then
    execute 'alter table public.books rename column organization_id to org_id';
  end if;
end $$;

alter table public.books add column if not exists org_id uuid references public.orgs(id) on delete cascade;
alter table public.books add column if not exists user_id uuid references auth.users(id) on delete cascade;
-- De-duplicate active books before enforcing uniqueness
with ranked_user as (
  select id, user_id, name, deleted_at, updated_at, created_at,
         row_number() over (
           partition by user_id, name
           order by (deleted_at is null) desc, coalesce(updated_at, created_at) desc, id
         ) rn
  from public.books
  where user_id is not null
)
update public.books b
set deleted_at = now()
from ranked_user r
where b.id = r.id and r.rn > 1 and b.deleted_at is null;

with ranked_org as (
  select id, org_id, name, deleted_at, updated_at, created_at,
         row_number() over (
           partition by org_id, name
           order by (deleted_at is null) desc, coalesce(updated_at, created_at) desc, id
         ) rn
  from public.books
  where org_id is not null
)
update public.books b
set deleted_at = now()
from ranked_org r
where b.id = r.id and r.rn > 1 and b.deleted_at is null;

-- Enforce uniqueness only among active (non-deleted) rows
create unique index if not exists books_org_name_uidx on public.books(org_id, name) where org_id is not null and deleted_at is null;
create unique index if not exists books_user_name_uidx on public.books(user_id, name) where user_id is not null and deleted_at is null;

-- Entries
create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  book_id uuid not null references public.books(id) on delete cascade,
  org_id uuid references public.orgs(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  type text not null check (type in ('in','out')),
  amount numeric(16,2) not null,
  currency char(3) not null default 'USD',
  category text,
  note text,
  contact text,
  payment_mode text,
  occurred_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Compatibility: add org_id column to entries if table existed previously without it
alter table public.entries add column if not exists org_id uuid;
-- Backfill entries.org_id from books.org_id when possible
update public.entries e
set org_id = b.org_id
from public.books b
where e.book_id = b.id and e.org_id is null;

-- Categories (per user or org)
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  user_id uuid references auth.users(id) on delete cascade,
  org_id uuid references public.orgs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.categories add column if not exists org_id uuid references public.orgs(id) on delete cascade;
alter table public.categories add column if not exists created_at timestamptz not null default now();
alter table public.categories add column if not exists updated_at timestamptz not null default now();
-- De-duplicate active categories before enforcing uniqueness
with ranked_cat_user as (
  select id, user_id, name, deleted_at, updated_at, created_at,
         row_number() over (
           partition by user_id, name
           order by (deleted_at is null) desc, coalesce(updated_at, created_at) desc, id
         ) rn
  from public.categories
  where user_id is not null
)
update public.categories c
set deleted_at = now()
from ranked_cat_user r
where c.id = r.id and r.rn > 1 and c.deleted_at is null;

with ranked_cat_org as (
  select id, org_id, name, deleted_at, updated_at, created_at,
         row_number() over (
           partition by org_id, name
           order by (deleted_at is null) desc, coalesce(updated_at, created_at) desc, id
         ) rn
  from public.categories
  where org_id is not null
)
update public.categories c
set deleted_at = now()
from ranked_cat_org r
where c.id = r.id and r.rn > 1 and c.deleted_at is null;

-- Enforce uniqueness only among active (non-deleted) rows
create unique index if not exists categories_user_name_uidx on public.categories(user_id, name) where user_id is not null and deleted_at is null;
create unique index if not exists categories_org_name_uidx on public.categories(org_id, name) where org_id is not null and deleted_at is null;

-- Tags (org scoped)
create table if not exists public.tags (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  org_id uuid references public.orgs(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
alter table public.tags add column if not exists org_id uuid references public.orgs(id) on delete cascade;
-- De-duplicate active tags before enforcing uniqueness
with ranked_tags as (
  select id, org_id, name, deleted_at, updated_at, created_at,
         row_number() over (
           partition by org_id, name
           order by (deleted_at is null) desc, coalesce(updated_at, created_at) desc, id
         ) rn
  from public.tags
  where org_id is not null
)
update public.tags t
set deleted_at = now()
from ranked_tags r
where t.id = r.id and r.rn > 1 and t.deleted_at is null;

-- Enforce uniqueness only among active (non-deleted) rows
create unique index if not exists tags_org_name_uidx on public.tags(org_id, name) where deleted_at is null;

-- Invites
create table if not exists public.org_invites (
  token uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  email text not null,
  role text not null check (role in ('admin','member','viewer')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted boolean not null default false
);

-- Business Invites
create table if not exists public.business_invites (
  token uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  email text not null,
  role text not null check (role in ('admin','member','viewer')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '14 days'),
  accepted boolean not null default false
);

-- Updated at triggers
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end$$;

-- Analytics events (lightweight telemetry) -----------------------------------------------------
create table if not exists public.analytics_events (
  id bigserial primary key,
  user_id uuid references auth.users(id) on delete cascade,
  name text not null,
  ts timestamptz not null default now(),
  props jsonb,
  aggregated_count integer not null default 1,
  created_at timestamptz not null default now()
);

-- Helpful indexes for faster queue draining / retention
create index if not exists analytics_events_user_id_idx on public.analytics_events(user_id);
create index if not exists analytics_events_ts_idx on public.analytics_events(ts);

alter table public.analytics_events enable row level security;

drop policy if exists analytics_events_select on public.analytics_events;
create policy analytics_events_select on public.analytics_events
  for select using (user_id = auth.uid());

drop policy if exists analytics_events_insert on public.analytics_events;
create policy analytics_events_insert on public.analytics_events
  for insert with check (user_id = auth.uid());

-- Optional retention pruning (example only; requires pg_cron extension availability)
-- delete from public.analytics_events where created_at < now() - interval '30 days';
-- End analytics -------------------------------------------------------------------------------

-- Businesses & multi-business support ---------------------------------------------------------
-- (Merged from supabase_migration_businesses.sql)

-- 1. Businesses table
create table if not exists public.businesses (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references public.orgs(id) on delete cascade,
  name text not null,
  color text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
  -- NOTE: Postgres does not allow a WHERE clause directly on a table-level UNIQUE constraint definition.
  -- We instead create a partial unique index (idempotent) below to enforce uniqueness of active names.
  -- (Leaving this placeholder comment for clarity; no direct UNIQUE here to avoid migration syntax error.)
);

-- Enforce uniqueness of active (non-deleted) business names per org via partial index
create unique index if not exists businesses_org_name_uidx on public.businesses(org_id, name) where deleted_at is null;

-- 2. Business members
create table if not exists public.business_members (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner','admin','member','viewer')),
  created_at timestamptz not null default now(),
  primary key (business_id, user_id)
);

-- 3. Books: add business_id (if not exists) and backfill default business per org
alter table public.books add column if not exists business_id uuid references public.businesses(id) on delete cascade;

-- (Safety) Repair any orphaned book org references so FK insert into businesses won't fail
-- This can happen if books.org_id contains IDs not present in orgs due to earlier partial data loads.
insert into public.orgs (id, name, created_at, updated_at)
select distinct b.org_id, 'Recovered Org', now(), now()
from public.books b
left join public.orgs o on o.id = b.org_id
where b.org_id is not null and o.id is null;

with orgs_needing as (
  select distinct org_id from public.books b
  where b.org_id is not null and b.business_id is null
)
insert into public.businesses (id, org_id, name, color)
select gen_random_uuid(), o.org_id, 'Main Business', '#3B82F6'
from orgs_needing o
where not exists (
  select 1 from public.businesses b2 where b2.org_id = o.org_id and b2.deleted_at is null
);

update public.books b
set business_id = (
  select id from public.businesses bus where bus.org_id = b.org_id and bus.deleted_at is null order by created_at asc limit 1
)
where b.org_id is not null and b.business_id is null;

-- 4. Trigger to ensure org_id stays synced from business
create or replace function public.sync_book_org()
returns trigger language plpgsql as $$
begin
  if new.business_id is not null then
    select bus.org_id into new.org_id from public.businesses bus where bus.id = new.business_id;
  end if;
  return new;
end$$;

drop trigger if exists trg_books_sync_org on public.books;
create trigger trg_books_sync_org before insert or update on public.books
  for each row execute function public.sync_book_org();

-- 5. Updated_at trigger for businesses
drop trigger if exists trg_businesses_updated on public.businesses;
create trigger trg_businesses_updated before update on public.businesses for each row execute function public.set_updated_at();

-- 6. Helper functions for business membership / admin (reuse org membership fallback)
create or replace function public.is_business_member(p_business_id uuid)
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.business_members bm where bm.business_id = p_business_id and bm.user_id = auth.uid()
  ) or exists (
    select 1 from public.businesses b join public.org_members om on om.org_id = b.org_id
    where b.id = p_business_id and om.user_id = auth.uid()
  );
$$;

create or replace function public.is_business_admin(p_business_id uuid)
returns boolean language sql security definer set search_path = public as $$
  select exists (
    select 1 from public.business_members bm where bm.business_id = p_business_id and bm.user_id = auth.uid() and bm.role in ('owner','admin')
  ) or exists (
    select 1 from public.businesses b join public.org_members om on om.org_id = b.org_id
    where b.id = p_business_id and om.user_id = auth.uid() and om.role in ('owner','admin')
  );
$$;

-- 7. RLS enable
alter table public.businesses enable row level security;
alter table public.business_members enable row level security;

-- Enable RLS for business invites
alter table public.business_invites enable row level security;

-- 8. Policies
drop policy if exists businesses_select on public.businesses;
create policy businesses_select on public.businesses
  for select using (public.is_org_member(org_id));
drop policy if exists businesses_insert on public.businesses;
create policy businesses_insert on public.businesses
  for insert with check (public.is_org_admin(org_id));
drop policy if exists businesses_update on public.businesses;
create policy businesses_update on public.businesses
  for update using (public.is_business_admin(id)) with check (public.is_business_admin(id));
drop policy if exists businesses_delete on public.businesses;
create policy businesses_delete on public.businesses
  for delete using (public.is_business_admin(id));

drop policy if exists business_members_select on public.business_members;
create policy business_members_select on public.business_members
  for select using (public.is_business_member(business_id));
drop policy if exists business_members_insert on public.business_members;
create policy business_members_insert on public.business_members
  for insert with check (public.is_business_admin(business_id));
drop policy if exists business_members_update on public.business_members;
create policy business_members_update on public.business_members
  for update using (public.is_business_admin(business_id)) with check (public.is_business_admin(business_id));
drop policy if exists business_members_delete on public.business_members;
create policy business_members_delete on public.business_members
  for delete using (public.is_business_admin(business_id));

-- Business invite policies
drop policy if exists business_invites_select on public.business_invites;
create policy business_invites_select on public.business_invites
  for select using (public.is_business_admin(business_id));
drop policy if exists business_invites_insert on public.business_invites;
create policy business_invites_insert on public.business_invites
  for insert with check (public.is_business_admin(business_id));
drop policy if exists business_invites_update on public.business_invites;
create policy business_invites_update on public.business_invites
  for update using (public.is_business_admin(business_id)) with check (public.is_business_admin(business_id));
drop policy if exists business_invites_delete on public.business_invites;
create policy business_invites_delete on public.business_invites
  for delete using (public.is_business_admin(business_id));

-- 9. Adjust books policy (defer full rewrite; legacy policy remains until future cleanup)
-- NOTE: Comprehensive replacement will happen after legacy org-only path is deprecated.

-- 10. push_business RPC & updated push_book supporting business_id
do $$
declare r record; begin
  for r in (
    select format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)) as fn
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public' and p.proname in ('push_business','push_book')
  ) loop
    execute 'drop function if exists '|| r.fn || ' cascade';
  end loop;
end $$;

create or replace function public.push_business(
  p_id uuid,
  p_org_id uuid,
  p_name text,
  p_color text default '#3B82F6',
  p_deleted_at timestamptz default null,
  p_updated_at timestamptz default null
) returns void language plpgsql security definer set search_path = public as $$
BEGIN
  if not public.is_org_admin(p_org_id) then
    raise exception 'permission denied';
  end if;
  insert into public.businesses as b (id, org_id, name, color, deleted_at, updated_at)
  values (p_id, p_org_id, p_name, p_color, p_deleted_at, coalesce(p_updated_at, now()))
  on conflict (id) do update set
    name = coalesce(excluded.name, b.name),
    color = coalesce(excluded.color, b.color),
    deleted_at = excluded.deleted_at,
    updated_at = excluded.updated_at;
END$$;

-- 11. Indexes
create index if not exists idx_businesses_org_id on public.businesses(org_id);
create index if not exists idx_books_business_id on public.books(business_id);

-- 12. Seed business_members from org_members for existing businesses
insert into public.business_members (business_id, user_id, role)
select b.id, om.user_id, om.role
from public.businesses b
join public.org_members om on om.org_id = b.org_id
on conflict (business_id, user_id) do nothing;

-- End businesses ------------------------------------------------------------------------------

drop trigger if exists trg_books_updated on public.books;
create trigger trg_books_updated before update on public.books for each row execute function public.set_updated_at();
drop trigger if exists trg_entries_updated on public.entries;
create trigger trg_entries_updated before update on public.entries for each row execute function public.set_updated_at();
drop trigger if exists trg_categories_updated on public.categories;
create trigger trg_categories_updated before update on public.categories for each row execute function public.set_updated_at();
drop trigger if exists trg_tags_updated on public.tags;
create trigger trg_tags_updated before update on public.tags for each row execute function public.set_updated_at();

-- Ensure org owner defaults to current user when inserting
create or replace function public.set_org_owner()
returns trigger language plpgsql security definer as $$
begin
  if new.owner_id is null then
    new.owner_id := auth.uid();
  end if;
  return new;
end$$;

drop trigger if exists trg_orgs_owner on public.orgs;
create trigger trg_orgs_owner before insert on public.orgs for each row execute function public.set_org_owner();

-- RLS enable
alter table public.orgs enable row level security;
alter table public.org_members enable row level security;
alter table public.books enable row level security;
alter table public.entries enable row level security;
alter table public.categories enable row level security;
alter table public.tags enable row level security;
alter table public.org_invites enable row level security;

-- Helper functions to avoid recursive policies
create or replace function public.is_org_member(p_org_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.org_members m
    where m.org_id = p_org_id and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_org_admin(p_org_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.org_members m
    where m.org_id = p_org_id and m.user_id = auth.uid() and m.role in ('owner','admin')
  );
$$;

create or replace function public.is_org_owner(p_org_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.orgs o where o.id = p_org_id and o.owner_id = auth.uid()
  );
$$;

create or replace function public.can_remove_member(p_org_id uuid, p_member_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  with owner as (
    select owner_id from public.orgs where id = p_org_id
  )
  select exists (
    select 1 from owner o where o.owner_id = auth.uid() and p_member_id <> o.owner_id
  );
$$;

create or replace function public.can_self_leave(p_org_id uuid, p_member_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select (p_member_id = auth.uid() and not public.is_org_owner(p_org_id));
$$;

create or replace function public.can_manage_org(p_org_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select (
    exists (select 1 from public.orgs o where o.id = p_org_id and o.owner_id = auth.uid())
    or public.is_org_admin(p_org_id)
  );
$$;

-- RLS policies
drop policy if exists orgs_select on public.orgs;
create policy orgs_select on public.orgs
  for select using (public.is_org_member(id) or owner_id = auth.uid());

drop policy if exists orgs_insert on public.orgs;
create policy orgs_insert on public.orgs
  for insert with check (auth.uid() is not null);

drop policy if exists orgs_delete on public.orgs;
create policy orgs_delete on public.orgs
  for delete using (owner_id = auth.uid());

drop policy if exists org_members_select on public.org_members;
create policy org_members_select on public.org_members
  for select using (user_id = auth.uid() or public.can_manage_org(org_id));

drop policy if exists org_members_insert on public.org_members;
create policy org_members_insert on public.org_members
  for insert with check (public.is_org_owner(org_id));

drop policy if exists org_members_update on public.org_members;
create policy org_members_update on public.org_members
  for update using (public.is_org_owner(org_id)) with check (public.is_org_owner(org_id));

drop policy if exists org_members_delete on public.org_members;
create policy org_members_delete on public.org_members
  for delete using (
    public.can_remove_member(org_id, user_id)
    or public.can_self_leave(org_id, user_id)
  );

drop policy if exists books_select on public.books;
create policy books_select on public.books
  for select using ((org_id is not null and public.is_org_member(org_id)) or user_id = auth.uid());

drop policy if exists books_insert on public.books;
create policy books_insert on public.books
  for insert with check (
    (org_id is not null and public.is_org_admin(org_id))
    or (org_id is null and user_id = auth.uid())
  );

drop policy if exists books_update on public.books;
create policy books_update on public.books
  for update using (
    (org_id is not null and public.is_org_owner(org_id))
    or (org_id is null and user_id = auth.uid())
  ) with check (
    (org_id is not null and public.is_org_owner(org_id))
    or (org_id is null and user_id = auth.uid())
  );

drop policy if exists books_delete on public.books;
create policy books_delete on public.books
  for delete using (
    (org_id is not null and public.is_org_owner(org_id))
    or (org_id is null and user_id = auth.uid())
  );

drop policy if exists entries_select on public.entries;
create policy entries_select on public.entries
  for select using ((org_id is not null and public.is_org_member(org_id)) or user_id = auth.uid());

drop policy if exists entries_insert on public.entries;
create policy entries_insert on public.entries
  for insert with check (
    (org_id is not null and user_id = auth.uid() and public.is_org_member(org_id))
    or (org_id is null and user_id = auth.uid())
  );

drop policy if exists entries_update on public.entries;
create policy entries_update on public.entries
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists entries_delete on public.entries;
create policy entries_delete on public.entries
  for delete using (user_id = auth.uid());

drop policy if exists categories_select on public.categories;
create policy categories_select on public.categories
  for select using ((org_id is not null and public.is_org_member(org_id)) or user_id = auth.uid());

drop policy if exists tags_select on public.tags;
create policy tags_select on public.tags
  for select using (public.is_org_member(org_id));

-- RPCs (use security definer but validate membership/ownership)
-- Clean up any previous overloaded versions to avoid ambiguous RPC resolution
do $$
declare r record; begin
  for r in (
    select
      format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)) as fn
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in ('push_book','push_entry','push_category','push_tag','create_org_invite','accept_org_invite')
  ) loop
    execute 'drop function if exists '|| r.fn || ' cascade';
  end loop;
end $$;

-- Delete organization (owner-only) with cascade
create or replace function public.delete_org(p_org_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_org_owner(p_org_id) then
    raise exception 'permission denied: only owner can delete org';
  end if;
  delete from public.orgs where id = p_org_id;
end$$;

create or replace function public.push_book(
  p_id uuid,
  p_business_id uuid,
  p_org_id uuid,
  p_user_id uuid,
  p_name text default null,
  p_color text default '#3B82F6',
  p_deleted_at timestamptz default null,
  p_updated_at timestamptz default null
) returns void language plpgsql security definer set search_path = public as $$
declare
  v_user uuid := coalesce(p_user_id, auth.uid());
  v_business uuid := p_business_id;
begin
  if v_business is null and p_org_id is not null then
    select id into v_business
    from public.businesses
    where org_id = p_org_id and deleted_at is null
    order by created_at asc
    limit 1;
    if v_business is null then
      insert into public.businesses(org_id, name, color)
      values (p_org_id, 'Main Business', '#3B82F6')
      returning id into v_business;
    end if;
  end if;

  if v_business is not null then
    if not public.is_business_admin(v_business) then
      raise exception 'permission denied: not business admin';
    end if;
  else
    if v_user is distinct from auth.uid() then
      raise exception 'permission denied: not owner';
    end if;
  end if;

  insert into public.books as t (id, business_id, org_id, user_id, name, color, deleted_at, updated_at)
  values (
    p_id,
    v_business,
    (select org_id from public.businesses where id = v_business),
    case when v_business is null then v_user else null end,
    coalesce(p_name, 'Book'),
    coalesce(p_color, '#3B82F6'),
    p_deleted_at,
    coalesce(p_updated_at, now())
  )
  on conflict (id) do update set
    business_id = excluded.business_id,
    org_id = excluded.org_id,
    user_id = excluded.user_id,
    name = coalesce(excluded.name, t.name),
    color = coalesce(excluded.color, t.color),
    deleted_at = excluded.deleted_at,
    updated_at = excluded.updated_at
  where (v_business is not null and public.is_business_admin(v_business))
     or public.is_org_owner(coalesce(excluded.org_id, t.org_id));
end$$;

create or replace function public.push_entry(
  p_id uuid,
  p_book_id uuid default null,
  p_type text default null,
  p_amount numeric default null,
  p_currency char(3) default null,
  p_category text default null,
  p_note text default null,
  p_contact text default null,
  p_payment_mode text default null,
  p_occurred_at timestamptz default null,
  p_deleted_at timestamptz default null,
  p_updated_at timestamptz default null
) returns void language plpgsql security definer as $$
declare
  v_book record;
  v_type text := case when lower(p_type) in ('in','out') then lower(p_type) else 'out' end;
begin
  if p_book_id is null then
    -- Delete or update-only path: update existing entry limited to the author
    update public.entries e
      set deleted_at = coalesce(p_deleted_at, e.deleted_at),
          updated_at = coalesce(p_updated_at, now())
    where e.id = p_id and e.user_id = auth.uid();
    return;
  end if;

  select b.*, b.org_id as bid_org into v_book from public.books b where b.id = p_book_id;
  if v_book is null then
    raise exception 'book not found';
  end if;
  if v_book.org_id is not null then
    if not exists (select 1 from public.org_members m where m.org_id = v_book.org_id and m.user_id = auth.uid()) then
      raise exception 'permission denied: not a member of org';
    end if;
  else
    if v_book.user_id is distinct from auth.uid() then
      raise exception 'permission denied: not book owner';
    end if;
  end if;

  insert into public.entries as e (
    id, book_id, org_id, user_id, type, amount, currency, category, note, contact, payment_mode, occurred_at, deleted_at, updated_at
  ) values (
    p_id, p_book_id, v_book.org_id, coalesce(v_book.user_id, auth.uid()), v_type, coalesce(p_amount, 0), coalesce(p_currency, 'USD'), p_category, p_note, p_contact, p_payment_mode, coalesce(p_occurred_at, now()), p_deleted_at, coalesce(p_updated_at, now())
  ) on conflict (id) do update set
    type = coalesce(excluded.type, e.type),
    amount = coalesce(excluded.amount, e.amount),
    currency = coalesce(excluded.currency, e.currency),
    category = coalesce(excluded.category, e.category),
    note = coalesce(excluded.note, e.note),
    contact = coalesce(excluded.contact, e.contact),
    payment_mode = coalesce(excluded.payment_mode, e.payment_mode),
    occurred_at = coalesce(excluded.occurred_at, e.occurred_at),
    deleted_at = coalesce(excluded.deleted_at, e.deleted_at),
    updated_at = excluded.updated_at,
    org_id = v_book.org_id
  where e.user_id = auth.uid();
end$$;

create or replace function public.push_category(
  p_id uuid,
  p_name text,
  p_org_id uuid,
  p_user_id uuid,
  p_deleted_at timestamptz,
  p_updated_at timestamptz
) returns void language plpgsql security definer as $$
begin
  if p_org_id is not null then
    if not exists (select 1 from public.org_members m where m.org_id = p_org_id and m.user_id = auth.uid()) then
      raise exception 'permission denied';
    end if;
  else
    if coalesce(p_user_id, auth.uid()) is distinct from auth.uid() then
      raise exception 'permission denied';
    end if;
  end if;
  insert into public.categories as c (id, name, org_id, user_id, deleted_at, updated_at)
  values (p_id, p_name, p_org_id, case when p_org_id is null then coalesce(p_user_id, auth.uid()) else null end, p_deleted_at, coalesce(p_updated_at, now()))
  on conflict(id) do update set
    name = excluded.name,
    org_id = excluded.org_id,
    user_id = excluded.user_id,
    deleted_at = excluded.deleted_at,
    updated_at = excluded.updated_at;
end$$;

create or replace function public.push_tag(
  p_id uuid,
  p_name text,
  p_org_id uuid,
  p_deleted_at timestamptz,
  p_updated_at timestamptz
) returns void language plpgsql security definer as $$
begin
  if not exists (select 1 from public.org_members m where m.org_id = p_org_id and m.user_id = auth.uid()) then
    raise exception 'permission denied';
  end if;
  insert into public.tags as t (id, name, org_id, deleted_at, updated_at)
  values (p_id, p_name, p_org_id, p_deleted_at, coalesce(p_updated_at, now()))
  on conflict (id) do update set
    name = excluded.name,
    org_id = excluded.org_id,
    deleted_at = excluded.deleted_at,
    updated_at = excluded.updated_at;
end$$;

-- Org invites
create or replace function public.create_org_invite(p_org_id uuid, p_email text, p_role text)
returns uuid language plpgsql security definer as $$
declare
  v_token uuid;
begin
  -- Only owner may invite
  if not public.is_org_owner(p_org_id) then
    raise exception 'permission denied';
  end if;
  v_token := gen_random_uuid();
  insert into public.org_invites(token, org_id, email, role) values (v_token, p_org_id, p_email, p_role);
  return v_token;
end$$;

create or replace function public.accept_org_invite(p_token uuid)
returns uuid language plpgsql security definer as $$
declare
  v_inv public.org_invites;
begin
  select * into v_inv from public.org_invites where token = p_token and accepted = false and expires_at > now();
  if not found then
    raise exception 'invalid or expired invite';
  end if;
  insert into public.org_members(org_id, user_id, role) values (v_inv.org_id, auth.uid(), v_inv.role)
    on conflict (org_id, user_id) do update set role = excluded.role;
  update public.org_invites set accepted = true where token = p_token;
  return v_inv.org_id;
end$$;

-- Direct add by email (alternative to deep link)
create or replace function public.add_member_by_email(p_org_id uuid, p_email text, p_role text)
returns void language plpgsql security definer as $$
declare
  v_user_id uuid;
begin
  -- Only owner may add members
  if not public.is_org_owner(p_org_id) then
    raise exception 'permission denied';
  end if;
  select id into v_user_id from auth.users where lower(email) = lower(p_email) limit 1;
  if v_user_id is null then
    raise exception 'user not found for email %', p_email;
  end if;
  insert into public.org_members(org_id, user_id, role) values (p_org_id, v_user_id, p_role)
    on conflict (org_id, user_id) do update set role = excluded.role;
end$$;

-- Business invite functions
create or replace function public.create_business_invite(p_business_id uuid, p_email text, p_role text)
returns uuid language plpgsql security definer as $$
declare
  v_token uuid;
begin
  -- Only business admin may invite
  if not public.is_business_admin(p_business_id) then
    raise exception 'permission denied';
  end if;
  v_token := gen_random_uuid();
  insert into public.business_invites(token, business_id, email, role) values (v_token, p_business_id, p_email, p_role);
  return v_token;
end$$;

create or replace function public.accept_business_invite(p_token uuid)
returns uuid language plpgsql security definer as $$
declare
  v_inv public.business_invites;
begin
  select * into v_inv from public.business_invites where token = p_token and accepted = false and expires_at > now();
  if not found then
    raise exception 'invalid or expired invite';
  end if;
  insert into public.business_members(business_id, user_id, role) values (v_inv.business_id, auth.uid(), v_inv.role)
    on conflict (business_id, user_id) do update set role = excluded.role;
  update public.business_invites set accepted = true where token = p_token;
  return v_inv.business_id;
end$$;

-- Direct add by email for business
create or replace function public.add_business_member_by_email(p_business_id uuid, p_email text, p_role text)
returns void language plpgsql security definer as $$
declare
  v_user_id uuid;
begin
  -- Only business admin may add members
  if not public.is_business_admin(p_business_id) then
    raise exception 'permission denied';
  end if;
  select id into v_user_id from auth.users where lower(email) = lower(p_email) limit 1;
  if v_user_id is null then
    raise exception 'user not found for email %', p_email;
  end if;
  insert into public.business_members(business_id, user_id, role) values (p_business_id, v_user_id, p_role)
    on conflict (business_id, user_id) do update set role = excluded.role;
end$$;

-- Delete business function
create or replace function public.delete_business(p_business_id uuid)
returns void language plpgsql security definer as $$
begin
  if not public.is_business_admin(p_business_id) then
    raise exception 'permission denied: only business admin can delete';
  end if;
  -- Soft delete to preserve referential integrity
  update public.businesses set deleted_at = now() where id = p_business_id;
end$$;

-- Get business members with emails (RPC function since client can't join auth.users)
create or replace function public.can_access_business(p_business_id uuid)
returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then
    return false;
  end if;

  if exists (
    select 1
    from public.business_members bm
    where bm.business_id = p_business_id
      and bm.user_id = auth.uid()
  ) then
    return true;
  end if;

  if exists (
    select 1
    from public.businesses b
    join public.org_members om on om.org_id = b.org_id
    where b.id = p_business_id
      and om.user_id = auth.uid()
  ) then
    return true;
  end if;

  if exists (
    select 1
    from public.businesses b
    join public.orgs o on o.id = b.org_id
    where b.id = p_business_id
      and o.owner_id = auth.uid()
  ) then
    return true;
  end if;

  return false;
end$$;

create or replace function public.get_business_members(p_business_id uuid)
returns table(user_id uuid, email text, role text, created_at timestamptz)
language plpgsql security definer as $$
begin
  -- Check if user has access to this business
  if not public.can_access_business(p_business_id) then
    raise exception 'permission denied';
  end if;
  
  return query
  select 
    bm.user_id,
    au.email,
    bm.role,
    bm.created_at
  from public.business_members bm
  inner join auth.users au on au.id = bm.user_id
  where bm.business_id = p_business_id
  order by bm.created_at;
end$$;
