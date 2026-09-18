-- ============================================================
-- Jenash Tech CMS — Supabase schema (with name+PIN admin login)
-- Run this once in your Supabase project's SQL Editor
-- (Dashboard → SQL Editor → New query → paste → Run)
-- ============================================================

create extension if not exists "pgcrypto";

-- ============================================================
-- DATA TABLES
-- ============================================================

create table if not exists members (
  id uuid primary key default gen_random_uuid(),
  "createdAt" timestamptz default now(),
  name text not null,
  phone text,
  email text,
  gender text,
  department text,
  status text default 'Active',
  "joinDate" date,
  address text,
  notes text
);

create table if not exists attendance (
  id uuid primary key default gen_random_uuid(),
  "createdAt" timestamptz default now(),
  date date,
  event text,
  male int default 0,
  female int default 0,
  children int default 0,
  total int default 0,
  notes text
);

create table if not exists finances (
  id uuid primary key default gen_random_uuid(),
  "createdAt" timestamptz default now(),
  type text not null,
  date date,
  "memberName" text,
  category text,
  amount numeric not null default 0,
  notes text
);

create table if not exists events (
  id uuid primary key default gen_random_uuid(),
  "createdAt" timestamptz default now(),
  title text not null,
  date date,
  time text,
  location text,
  department text,
  status text default 'Upcoming',
  description text
);

create table if not exists departments (
  id uuid primary key default gen_random_uuid(),
  "createdAt" timestamptz default now(),
  name text not null,
  leader text,
  description text
);

create table if not exists announcements (
  id uuid primary key default gen_random_uuid(),
  "createdAt" timestamptz default now(),
  title text not null,
  message text not null,
  audience text default 'All Members',
  date date
);

create table if not exists settings (
  id text primary key,
  "churchName" text,
  branch text,
  currency text default 'GH₵'
);

-- ============================================================
-- ADMIN AUTH (name + PIN, no email) — hard-capped at 5 admins
-- ============================================================

create table if not exists admins (
  id uuid primary key default gen_random_uuid(),
  "createdAt" timestamptz default now(),
  name text not null unique,
  pin_hash text not null
);

create table if not exists admin_sessions (
  token uuid primary key default gen_random_uuid(),
  admin_id uuid not null references admins(id) on delete cascade,
  "createdAt" timestamptz default now(),
  "expiresAt" timestamptz not null
);

-- Hard cap: once 5 admin rows exist, no further inserts succeed — for
-- anyone, including someone running SQL directly. There is also no
-- "add admin" feature anywhere in the app, so this table is only ever
-- written to once, by you, in Supabase's SQL Editor.
create or replace function enforce_admin_limit()
returns trigger language plpgsql as $$
begin
  if (select count(*) from admins) >= 5 then
    raise exception 'Admin limit reached (5/5) — no further admins can be added.';
  end if;
  return new;
end;
$$;

drop trigger if exists admins_limit_trigger on admins;
create trigger admins_limit_trigger
before insert on admins
for each row execute function enforce_admin_limit();

-- ============================================================
-- LOCK DOWN DIRECT TABLE ACCESS
-- Enable RLS with NO policies on every table = deny-all for the
-- public "anon" key. The only way in is through the functions below,
-- which run as the table owner (SECURITY DEFINER) and therefore
-- bypass RLS themselves — but only after verifying a valid session.
-- ============================================================

alter table members enable row level security;
alter table attendance enable row level security;
alter table finances enable row level security;
alter table events enable row level security;
alter table departments enable row level security;
alter table announcements enable row level security;
alter table settings enable row level security;
alter table admins enable row level security;
alter table admin_sessions enable row level security;
-- (No policies created for any of the above = fully closed to anon.)

-- ============================================================
-- AUTH FUNCTIONS
-- ============================================================

-- Verifies a session token is valid and not expired; raises if not.
create or replace function require_admin(p_token uuid)
returns uuid language plpgsql security definer as $$
declare v_admin uuid;
begin
  select admin_id into v_admin
    from admin_sessions
    where token = p_token and "expiresAt" > now();
  if v_admin is null then
    raise exception 'Not authorized — please log in again.';
  end if;
  return v_admin;
end;
$$;

-- Logs in with name + PIN. Returns a session token valid for 12 hours.
create or replace function admin_login(p_name text, p_pin text)
returns table(token uuid, name text) language plpgsql security definer as $$
declare v_admin admins%rowtype; v_token uuid;
begin
  select * into v_admin from admins where lower(trim(name)) = lower(trim(p_name));
  if v_admin.id is null or v_admin.pin_hash <> crypt(p_pin, v_admin.pin_hash) then
    raise exception 'Invalid name or PIN';
  end if;
  v_token := gen_random_uuid();
  insert into admin_sessions (token, admin_id, "expiresAt")
    values (v_token, v_admin.id, now() + interval '12 hours');
  return query select v_token, v_admin.name;
end;
$$;

create or replace function admin_logout(p_token uuid)
returns void language plpgsql security definer as $$
begin
  delete from admin_sessions where token = p_token;
end;
$$;

-- ============================================================
-- GENERIC DATA ACCESS (all gated behind require_admin)
-- ============================================================

create or replace function app_list(p_token uuid, p_table text)
returns setof jsonb language plpgsql security definer as $$
declare allowed text[] := array['members','attendance','finances','events','departments','announcements'];
begin
  if not (p_table = any(allowed)) then raise exception 'Invalid table'; end if;
  perform require_admin(p_token);
  return query execute format('select to_jsonb(t.*) from %I t order by t."createdAt" desc limit 500', p_table);
end;
$$;

create or replace function app_insert(p_token uuid, p_table text, p_data jsonb)
returns jsonb language plpgsql security definer as $$
declare
  allowed text[] := array['members','attendance','finances','events','departments','announcements'];
  cols text; vals text; result jsonb;
begin
  if not (p_table = any(allowed)) then raise exception 'Invalid table'; end if;
  perform require_admin(p_token);
  select string_agg(format('%I', key), ', '), string_agg(format('%L', value), ', ')
    into cols, vals
    from jsonb_each_text(p_data);
  if cols is null then raise exception 'No data provided'; end if;
  execute format('insert into %I (%s) values (%s) returning to_jsonb(%I.*)', p_table, cols, vals, p_table)
    into result;
  return result;
end;
$$;

create or replace function app_update(p_token uuid, p_table text, p_id uuid, p_data jsonb)
returns void language plpgsql security definer as $$
declare
  allowed text[] := array['members','attendance','finances','events','departments','announcements'];
  set_sql text;
begin
  if not (p_table = any(allowed)) then raise exception 'Invalid table'; end if;
  perform require_admin(p_token);
  select string_agg(format('%I = %L', key, value), ', ')
    into set_sql
    from jsonb_each_text(p_data);
  if set_sql is null then return; end if;
  execute format('update %I set %s where id = %L', p_table, set_sql, p_id);
end;
$$;

create or replace function app_delete(p_token uuid, p_table text, p_id uuid)
returns void language plpgsql security definer as $$
declare allowed text[] := array['members','attendance','finances','events','departments','announcements'];
begin
  if not (p_table = any(allowed)) then raise exception 'Invalid table'; end if;
  perform require_admin(p_token);
  execute format('delete from %I where id = %L', p_table, p_id);
end;
$$;

create or replace function app_get_settings(p_token uuid)
returns jsonb language plpgsql security definer as $$
declare result jsonb;
begin
  perform require_admin(p_token);
  select to_jsonb(s.*) into result from settings s where id = 'church';
  return result;
end;
$$;

create or replace function app_save_settings(p_token uuid, p_data jsonb)
returns void language plpgsql security definer as $$
begin
  perform require_admin(p_token);
  insert into settings (id, "churchName", branch, currency)
    values ('church', p_data->>'churchName', p_data->>'branch', p_data->>'currency')
  on conflict (id) do update set
    "churchName" = excluded."churchName",
    branch = excluded.branch,
    currency = excluded.currency;
end;
$$;

-- ============================================================
-- GRANTS — only the functions above are reachable by the app's anon key
-- ============================================================

grant execute on function admin_login(text, text) to anon;
grant execute on function admin_logout(uuid) to anon;
grant execute on function app_list(uuid, text) to anon;
grant execute on function app_insert(uuid, text, jsonb) to anon;
grant execute on function app_update(uuid, text, uuid, jsonb) to anon;
grant execute on function app_delete(uuid, text, uuid) to anon;
grant execute on function app_get_settings(uuid) to anon;
grant execute on function app_save_settings(uuid, jsonb) to anon;

-- ============================================================
-- ONE-TIME SETUP: create your 5 named admins
-- ============================================================
-- Run this block ONCE, replacing the names and PINs (4–6 digits,
-- numbers only recommended). This is the ONLY way admins ever get
-- created — there is no "add admin" button anywhere in the app, and
-- the trigger above blocks a 6th row even here, permanently.
--
insert into admins (name, pin_hash) values
('Emmanuel Ofosu Yeboah', crypt('1234', gen_salt('bf')));
--   ('Admin Two',             crypt('2345', gen_salt('bf'))),
--   ('Admin Three',           crypt('3456', gen_salt('bf'))),
--   ('Admin Four',            crypt('4567', gen_salt('bf'))),
--   ('Admin Five',            crypt('5678', gen_salt('bf')));
