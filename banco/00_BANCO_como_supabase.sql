set client_min_messages = warning;
-- =============================================================================
-- 00_BANCO_como_supabase.sql
-- Imita, en un PostgreSQL 16 local, lo que Supabase ya trae hecho, para que los
-- archivos de sql/ se puedan probar aquí exactamente como correrán en producción.
--
-- NO se ejecuta en Supabase. Solo en el banco local.
--
-- Qué imita:
--   · roles anon, authenticated y service_role
--   · esquema auth con la tabla auth.users y las funciones auth.uid() y auth.role()
--   · esquema extensions
-- Cómo se simula un usuario en una prueba:
--   select banco_como('<uuid del usuario>');   -- actúa como authenticated con ese uid
--   select banco_como_anonimo();               -- actúa como anon
--   reset role;                                -- vuelve a ser el dueño de la base
-- =============================================================================

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin noinherit;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin noinherit bypassrls;
  end if;
end $$;

-- El usuario que reconstruye el banco debe poder adoptar los tres roles
do $$
begin
  execute format('grant anon, authenticated, service_role to %I', current_user);
end $$;

create schema if not exists auth;
create schema if not exists extensions;

grant usage on schema public, auth, extensions to anon, authenticated, service_role;

create table if not exists auth.users (
  id                  uuid primary key default gen_random_uuid(),
  email               text unique,
  raw_user_meta_data  jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now()
);

-- auth.uid(): en Supabase sale del JWT. Aquí sale de una variable de sesión.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create or replace function auth.role() returns text
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.role', true), ''), 'anon')
$$;

grant execute on function auth.uid(), auth.role() to anon, authenticated, service_role;

-- Supabase concede por omisión permisos amplios sobre lo que se cree en public.
-- Se imitan aquí para que el banco no sea más seguro que producción: cada archivo de
-- sql/ debe retirar explícitamente lo que no corresponde.
alter default privileges in schema public grant all on tables    to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Ayudas del banco para las pruebas (no existen en Supabase)
-- -----------------------------------------------------------------------------
create or replace function public.banco_como(p_uid uuid) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid::text, false);
  perform set_config('request.jwt.claim.role', 'authenticated', false);
  execute 'set role authenticated';
end $$;

create or replace function public.banco_como_anonimo() returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('request.jwt.claim.role', 'anon', false);
  execute 'set role anon';
end $$;

-- Crea una cuenta de acceso como lo haría el panel de Supabase.
create or replace function public.banco_crear_cuenta(p_email text, p_nombre text default null)
returns uuid language plpgsql as $$
declare v uuid;
begin
  insert into auth.users(email, raw_user_meta_data)
  values (p_email, case when p_nombre is null then '{}'::jsonb
                        else jsonb_build_object('nombre', p_nombre) end)
  returning id into v;
  return v;
end $$;

grant execute on function public.banco_como(uuid), public.banco_como_anonimo() to public;
