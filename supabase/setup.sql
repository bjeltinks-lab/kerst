-- =====================================================================
--  Kerst Lootjes — database setup voor Supabase
--  Plak dit hele bestand in Supabase → SQL Editor → Run.
--  Daarna wachtwoorden.sql draaien (staat NIET in git).
--
--  Veiligheid: de tabellen zijn volledig afgesloten (RLS aan, geen policies,
--  geen grants). De website kan alleen de kerst_* functies hieronder
--  aanroepen; die checken zelf het sessie-token. Zo kan niemand via de
--  browser zien wie wie heeft getrokken.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- ---------- tabellen ----------
create table if not exists public.members (
  name         text primary key,
  sort         int  not null default 0,
  pass_hash    text not null,
  photo        text,                         -- verkleinde foto als data-URL
  wishes       text[] not null default '{}',
  profile_done boolean not null default false,
  tour_done    boolean not null default false
);

create table if not exists public.sessions (
  token      uuid primary key default gen_random_uuid(),
  name       text not null references public.members(name) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.draws (
  drawer   text primary key references public.members(name) on delete cascade,
  drawn    text not null unique references public.members(name) on delete cascade,
  drawn_at timestamptz not null default now(),
  check (drawer <> drawn)
);

alter table public.members  enable row level security;
alter table public.sessions enable row level security;
alter table public.draws    enable row level security;
revoke all on public.members, public.sessions, public.draws from public;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on public.members, public.sessions, public.draws from anon, authenticated';
  end if;
end $$;

-- ---------- interne helpers (niet aanroepbaar vanaf de website) ----------
create or replace function public.kerst_whoami(p_token uuid)
returns text language plpgsql security definer set search_path = public as $$
declare v text;
begin
  select name into v from sessions where token = p_token;
  if v is null then
    raise exception 'Je sessie is verlopen, log opnieuw in' using errcode = 'P0001', hint = 'session';
  end if;
  return v;
end $$;

create or replace function public.kerst_state_for(p_me text)
returns json language sql security definer set search_path = public as $$
  select json_build_object(
    'me', (select json_build_object('name', m.name, 'photo', m.photo, 'wishes', m.wishes,
                                    'profile_done', m.profile_done, 'tour_done', m.tour_done)
           from members m where m.name = p_me),
    'names', (select json_agg(name order by sort, name) from members),
    'draw', (select json_build_object('name', m.name, 'photo', m.photo, 'wishes', m.wishes,
                                      'drawn_at', d.drawn_at)
             from draws d join members m on m.name = d.drawn where d.drawer = p_me)
  )
$$;

-- Kiest een willekeurige naam voor p_me uit de ongetrokken namen.
-- Voorkomt dat de laatste trekker alleen zichzelf overhoudt.
create or replace function public.kerst_pick(p_me text, p_exclude text)
returns text language plpgsql security definer set search_path = public as $$
declare
  v_left  int;
  v_last  text;
  v_pick  text;
begin
  -- wie moet (naast mij) nog trekken?
  select count(*), min(m.name) into v_left, v_last
  from members m
  where m.name <> p_me and not exists (select 1 from draws d where d.drawer = m.name);

  -- precies één ander moet nog, en die zit zelf nog in de pot:
  -- dan moet ik die nemen, anders blijft hij met zichzelf over.
  if v_left = 1 and not exists (select 1 from draws d where d.drawn = v_last) then
    if v_last is distinct from p_exclude then return v_last; end if;
    return null;
  end if;

  select m.name into v_pick
  from members m
  where m.name <> p_me
    and m.name is distinct from p_exclude
    and not exists (select 1 from draws d where d.drawn = m.name)
  order by random()
  limit 1;
  return v_pick;
end $$;

-- ---------- publieke functies (de website roept deze aan) ----------
create or replace function public.kerst_login(p_name text, p_password text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_name text; v_hash text; v_token uuid;
begin
  select name, pass_hash into v_name, v_hash
  from members where lower(name) = lower(trim(p_name));
  if v_name is null or v_hash <> crypt(p_password, v_hash) then
    raise exception 'Naam of wachtwoord klopt niet' using errcode = 'P0001';
  end if;
  insert into sessions(name) values (v_name) returning token into v_token;
  return json_build_object('token', v_token, 'state', kerst_state_for(v_name));
end $$;

create or replace function public.kerst_logout(p_token uuid)
returns void language sql security definer set search_path = public as $$
  delete from sessions where token = p_token
$$;

create or replace function public.kerst_state(p_token uuid)
returns json language plpgsql security definer set search_path = public as $$
begin
  return kerst_state_for(kerst_whoami(p_token));
end $$;

create or replace function public.kerst_save_profile(p_token uuid, p_wishes text[], p_photo text default null)
returns json language plpgsql security definer set search_path = public as $$
declare v_me text := kerst_whoami(p_token); v_clean text[];
begin
  select coalesce(array_agg(left(trim(w), 200) order by i), '{}')
    into v_clean
  from unnest(p_wishes[1:10]) with ordinality as t(w, i);

  if p_photo is not null and p_photo <> '' then
    if p_photo not like 'data:image/%' or length(p_photo) > 600000 then
      raise exception 'Deze foto is te groot of geen afbeelding' using errcode = 'P0001';
    end if;
  end if;

  update members set
    wishes = v_clean,
    photo = case when p_photo is null then photo when p_photo = '' then null else p_photo end,
    profile_done = true
  where name = v_me;
  return kerst_state_for(v_me);
end $$;

create or replace function public.kerst_tour_done(p_token uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_me text := kerst_whoami(p_token);
begin
  update members set tour_done = true where name = v_me;
  return kerst_state_for(v_me);
end $$;

create or replace function public.kerst_draw(p_token uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_me text := kerst_whoami(p_token); v_pick text;
begin
  perform pg_advisory_xact_lock(20261225);          -- één trekking tegelijk
  if exists (select 1 from draws where drawer = v_me) then
    return kerst_state_for(v_me);                   -- al getrokken: niks veranderen
  end if;
  v_pick := kerst_pick(v_me, null);
  if v_pick is null then
    raise exception 'Er zitten geen namen meer in de pot' using errcode = 'P0001';
  end if;
  insert into draws(drawer, drawn) values (v_me, v_pick);
  return kerst_state_for(v_me);
end $$;

create or replace function public.kerst_redraw(p_token uuid)
returns json language plpgsql security definer set search_path = public as $$
declare v_me text := kerst_whoami(p_token); v_old text; v_pick text;
begin
  perform pg_advisory_xact_lock(20261225);
  delete from draws where drawer = v_me returning drawn into v_old;   -- oude naam terug in de pot
  v_pick := kerst_pick(v_me, v_old);                                   -- maar niet dezelfde terugkrijgen
  if v_pick is null then
    -- exception = hele transactie terugdraaien, je houdt je oude naam
    raise exception 'Er is geen andere naam meer over, je houdt %', coalesce(v_old, 'je huidige naam')
      using errcode = 'P0001';
  end if;
  insert into draws(drawer, drawn) values (v_me, v_pick);
  return kerst_state_for(v_me);
end $$;

-- ---------- rechten ----------
revoke execute on function public.kerst_whoami(uuid), public.kerst_state_for(text),
  public.kerst_pick(text, text) from public;

do $$ begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke execute on function public.kerst_whoami(uuid), public.kerst_state_for(text), public.kerst_pick(text, text) from anon, authenticated';
    execute 'grant execute on function public.kerst_login(text, text), public.kerst_logout(uuid), public.kerst_state(uuid), public.kerst_save_profile(uuid, text[], text), public.kerst_tour_done(uuid), public.kerst_draw(uuid), public.kerst_redraw(uuid) to anon';
  end if;
end $$;
