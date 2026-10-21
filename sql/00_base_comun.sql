-- =============================================================================
-- SGP · Sistema de Gestión de Proyectos · Grupo RefriAmerica
-- 00_base_comun.sql — versión de esquema 0.1
--
-- Qué crea:
--   1. Configuración del sistema y modo prueba / operación real
--   2. Roles del Departamento de Proyectos
--   3. Perfiles: la PERSONA, separada de la CUENTA de acceso (auth.users)
--   4. Llaves de permiso: fn_conduce() puede HACER, fn_ve_todo() puede VER
--   5. Avisos internos (notificaciones + fn_avisar)
--   6. Bitácora de auditoría
--   7. Funciones que llama la aplicación (rpc_*)
--   8. Comprobaciones finales: si algo no quedó como debe, el archivo se revierte entero
--
-- Se ejecuta en el editor SQL de Supabase, de una sola vez. Se puede volver a ejecutar.
-- Referencias: RFA-PRY-MAN-001 (procesos y roles) · Especificación del SGS v8.5 (patrones).
-- =============================================================================

-- Silencia los avisos de "no existe, se omite"; las comprobaciones finales sí se muestran.
set local client_min_messages = warning;

-- Para poder volver a ejecutar el archivo: las políticas dependen de las funciones llave,
-- así que se retiran primero y se recrean al final.
do $$
declare r record;
begin
  for r in select schemaname, tablename, policyname from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 1. Configuración y modo prueba
-- -----------------------------------------------------------------------------
create table if not exists public.sistema_config (
  id               boolean primary key default true check (id),   -- una sola fila
  modo             text    not null default 'prueba' check (modo in ('prueba', 'operacion')),
  version_esquema  text    not null,
  zona_horaria     text    not null default 'America/Caracas',
  actualizado_en   timestamptz not null default now()
);
insert into public.sistema_config (id, version_esquema) values (true, '0.1')
on conflict (id) do update set version_esquema = excluded.version_esquema, actualizado_en = now();

create table if not exists public.modo_bitacora (
  id          bigint generated always as identity primary key,
  modo_antes  text not null,
  modo_nuevo  text not null,
  motivo      text not null,
  perfil_id   uuid,
  en          timestamptz not null default now()
);

-- El modo vigente. Lo usan las columnas es_prueba (valor por omisión) y la política
-- restrictiva que separa lo registrado en prácticas de lo registrado en operación real.
create or replace function public.fn_modo_prueba() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select modo = 'prueba' from public.sistema_config where id), true)
$$;

-- -----------------------------------------------------------------------------
-- 2. Roles del departamento (RFA-PRY-MAN-001, sección 2.2)
--    Un perfil sin rol (null) existe pero no tiene permisos: es el estado de una cuenta
--    recién creada que la coordinación todavía no ha asignado.
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_type where typname = 'rol_usuario' and typnamespace = 'public'::regnamespace) then
    create type public.rol_usuario as enum (
      'admin',            -- administración del sistema
      'gerente',          -- Gerente de Ingeniería
      'coordinador',      -- Coordinador de Proyectos
      'ingeniero',        -- Ingenieros de Proyectos y de Automatización y Controles
      'control_gestion',  -- Ing. de Control de Gestión y Procedimientos
      'ventas',           -- Ventas: registra requerimientos, consulta lo suyo
      'construccion'      -- Construcción: consulta lo traspasado
    );
  end if;
end $$;

-- -----------------------------------------------------------------------------
-- 3. Perfiles: la persona
--    Por qué separar persona y cuenta (lección del SGS): una persona puede existir en el
--    sistema sin entrar nunca a la aplicación, y una cuenta puede crearse antes de que la
--    coordinación decida qué rol tiene. Si fueran lo mismo, habría que crear cuentas que no
--    se usan o dejar gente fuera del registro.
-- -----------------------------------------------------------------------------
create table if not exists public.perfiles (
  id              uuid primary key default gen_random_uuid(),
  auth_id         uuid unique references auth.users (id) on delete set null,
  nombre          text not null check (length(trim(nombre)) > 1),
  cargo           text,
  rol             public.rol_usuario,
  correo          text,
  telefono        text,
  disciplina      text check (disciplina in ('HV', 'AU', 'GE')),
  numero_civ      text,          -- inscripción en el Colegio de Ingenieros de Venezuela (firma de documentos)
  activo          boolean not null default true,
  retirado_motivo text,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now()
);
create unique index if not exists perfiles_correo_unico on public.perfiles (lower(correo)) where correo is not null;

-- -----------------------------------------------------------------------------
-- 4. Llaves de permiso
--    Separar VER de HACER evita dar permiso de escritura solo para permitir una consulta.
--    Son security definer para que las políticas puedan leer perfiles sin caer en recursión.
-- -----------------------------------------------------------------------------
drop function if exists public.fn_mi_perfil_id();
create function public.fn_mi_perfil_id() returns uuid
language sql stable security definer set search_path = public as $$
  select id from public.perfiles where auth_id = auth.uid() and activo
$$;

drop function if exists public.fn_mi_rol();
create function public.fn_mi_rol() returns public.rol_usuario
language sql stable security definer set search_path = public as $$
  select rol from public.perfiles where auth_id = auth.uid() and activo
$$;

-- Puede HACER: aprobar, asignar, administrar personal
drop function if exists public.fn_conduce();
create function public.fn_conduce() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.fn_mi_rol() in ('admin', 'gerente', 'coordinador'), false)
$$;

-- Puede VER todo el departamento
drop function if exists public.fn_ve_todo();
create function public.fn_ve_todo() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.fn_mi_rol() in ('admin', 'gerente', 'coordinador', 'control_gestion'), false)
$$;

drop function if exists public.fn_es_admin();
create function public.fn_es_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(public.fn_mi_rol() = 'admin', false)
$$;

-- -----------------------------------------------------------------------------
-- 5. Avisos internos
--    Todo aviso pasa por fn_avisar. La aplicación los lee en su latido (cada 30 s).
-- -----------------------------------------------------------------------------
create table if not exists public.notificaciones (
  id              bigint generated always as identity primary key,
  destinatario_id uuid not null references public.perfiles (id) on delete cascade,
  tipo            text not null,
  titulo          text not null,
  cuerpo          text,
  enlace          text,
  leida_en        timestamptz,
  creado_en       timestamptz not null default now(),
  es_prueba       boolean not null default public.fn_modo_prueba()
);
create index if not exists notificaciones_destinatario on public.notificaciones (destinatario_id, leida_en);

drop function if exists public.fn_avisar(uuid[], text, text, text, text);
create function public.fn_avisar(p_destinos uuid[], p_tipo text, p_titulo text,
                                 p_cuerpo text default null, p_enlace text default null)
returns integer language plpgsql security definer set search_path = public as $$
declare v integer;
begin
  insert into public.notificaciones (destinatario_id, tipo, titulo, cuerpo, enlace)
  select distinct d, p_tipo, p_titulo, p_cuerpo, p_enlace
  from unnest(p_destinos) as d
  where d is not null
    and exists (select 1 from public.perfiles p where p.id = d and p.activo);
  get diagnostics v = row_count;
  return v;
end $$;

-- -----------------------------------------------------------------------------
-- 6. Bitácora de auditoría (no se edita ni se borra)
-- -----------------------------------------------------------------------------
create table if not exists public.auditoria (
  id          bigint generated always as identity primary key,
  tabla       text not null,
  registro_id text not null,
  accion      text not null check (accion in ('alta', 'cambio', 'baja')),
  antes       jsonb,
  despues     jsonb,
  perfil_id   uuid,
  en          timestamptz not null default now()
);
create index if not exists auditoria_registro on public.auditoria (tabla, registro_id);

drop function if exists public.trg_auditar() cascade;
create function public.trg_auditar() returns trigger
language plpgsql security definer set search_path = public as $$
-- security definer es obligatorio: auditoria tiene RLS y no tiene política de escritura.
-- Sin privilegios de propietario el insert afectaría cero filas SIN dar error (la trampa
-- del RLS silencioso que el SGS encontró dos veces).
begin
  insert into public.auditoria (tabla, registro_id, accion, antes, despues, perfil_id)
  values (tg_table_name,
          coalesce(to_jsonb(new) ->> 'id', to_jsonb(old) ->> 'id'),
          case tg_op when 'INSERT' then 'alta' when 'UPDATE' then 'cambio' else 'baja' end,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end,
          public.fn_mi_perfil_id());
  return coalesce(new, old);
end $$;

drop trigger if exists trg_auditar_perfiles on public.perfiles;
create trigger trg_auditar_perfiles after insert or update or delete on public.perfiles
for each row execute function public.trg_auditar();

drop function if exists public.trg_actualizado_en() cascade;
create function public.trg_actualizado_en() returns trigger
language plpgsql as $$
begin new.actualizado_en := now(); return new; end $$;

drop trigger if exists trg_perfiles_actualizado on public.perfiles;
create trigger trg_perfiles_actualizado before update on public.perfiles
for each row execute function public.trg_actualizado_en();

-- -----------------------------------------------------------------------------
-- 3b. Alta automática de la ficha cuando se crea una cuenta
--     Si ya existe una ficha con ese correo y sin cuenta, la enlaza en lugar de crear otra:
--     en el SGS las fichas duplicadas aparecieron en cantidad durante la puesta en marcha.
-- -----------------------------------------------------------------------------
drop function if exists public.trg_nuevo_usuario() cascade;
create function public.trg_nuevo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id from public.perfiles
  where auth_id is null and correo is not null and lower(correo) = lower(new.email)
  limit 1;

  if v_id is not null then
    update public.perfiles set auth_id = new.id where id = v_id;
  else
    insert into public.perfiles (auth_id, nombre, correo)
    values (new.id,
            coalesce(nullif(trim(new.raw_user_meta_data ->> 'nombre'), ''), split_part(new.email, '@', 1)),
            new.email);
  end if;
  return new;
end $$;

drop trigger if exists trg_nuevo_usuario on auth.users;
create trigger trg_nuevo_usuario after insert on auth.users
for each row execute function public.trg_nuevo_usuario();

-- -----------------------------------------------------------------------------
-- 7. Funciones que llama la aplicación
-- -----------------------------------------------------------------------------

-- Lo primero que pide la aplicación al iniciar sesión.
drop function if exists public.rpc_mi_sesion();
create function public.rpc_mi_sesion() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p public.perfiles;
begin
  select * into p from public.perfiles where auth_id = auth.uid();
  if not found then
    raise exception 'Su cuenta no está vinculada a una ficha de personal. Avise a la Coordinación de Proyectos.';
  end if;
  if not p.activo then
    raise exception 'Su ficha de personal está retirada. Avise a la Coordinación de Proyectos.';
  end if;
  return jsonb_build_object(
    'perfil_id', p.id, 'nombre', p.nombre, 'cargo', p.cargo, 'rol', p.rol,
    'disciplina', p.disciplina,
    'modo', (select modo from public.sistema_config where id),
    'version_esquema', (select version_esquema from public.sistema_config where id),
    'zona_horaria', 'America/Caracas');
end $$;

-- Alta o edición de una ficha de personal.
drop function if exists public.rpc_personal_guardar(uuid, text, text, public.rol_usuario, text, text, text, text);
create function public.rpc_personal_guardar(
  p_id uuid, p_nombre text, p_cargo text, p_rol public.rol_usuario,
  p_correo text, p_telefono text, p_disciplina text, p_numero_civ text)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_rol_actual public.rol_usuario;
begin
  if not public.fn_conduce() then
    raise exception 'Solo la coordinación o la gerencia pueden registrar personal.';
  end if;
  if p_nombre is null or length(trim(p_nombre)) < 2 then
    raise exception 'El nombre es obligatorio.';
  end if;
  if p_disciplina is not null and p_disciplina not in ('HV', 'AU', 'GE') then
    raise exception 'Disciplina no válida: use HV, AU o GE.';
  end if;

  if p_id is not null then
    select rol into v_rol_actual from public.perfiles where id = p_id;
    if not found then raise exception 'La ficha indicada no existe.'; end if;
  end if;
  -- Solo un administrador otorga o retira el rol de administrador.
  if (p_rol = 'admin' or v_rol_actual = 'admin') and p_rol is distinct from v_rol_actual
     and not public.fn_es_admin() then
    raise exception 'Solo un administrador puede otorgar o retirar el rol de administrador.';
  end if;

  if p_id is null then
    insert into public.perfiles (nombre, cargo, rol, correo, telefono, disciplina, numero_civ)
    values (trim(p_nombre), p_cargo, p_rol, nullif(trim(p_correo), ''), p_telefono, p_disciplina, p_numero_civ)
    returning id into v_id;
  else
    update public.perfiles set nombre = trim(p_nombre), cargo = p_cargo, rol = p_rol,
           correo = nullif(trim(p_correo), ''), telefono = p_telefono,
           disciplina = p_disciplina, numero_civ = p_numero_civ
    where id = p_id returning id into v_id;
  end if;
  return v_id;
end $$;

-- Retiro (baja lógica): la ficha nunca se borra, porque su historial la referencia.
drop function if exists public.rpc_personal_retirar(uuid, text);
create function public.rpc_personal_retirar(p_id uuid, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.fn_conduce() then
    raise exception 'Solo la coordinación o la gerencia pueden retirar personal.';
  end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then
    raise exception 'Indique el motivo del retiro.';
  end if;
  if p_id = public.fn_mi_perfil_id() then
    raise exception 'No puede retirar su propia ficha.';
  end if;
  if exists (select 1 from public.perfiles where id = p_id and rol = 'admin') and not public.fn_es_admin() then
    raise exception 'Solo un administrador puede retirar a otro administrador.';
  end if;
  update public.perfiles set activo = false, retirado_motivo = trim(p_motivo) where id = p_id;
  if not found then raise exception 'La ficha indicada no existe.'; end if;
end $$;

-- Enlaza una cuenta de acceso (por su correo) con una ficha existente.
-- Si al crear la cuenta se generó una ficha automática vacía, esa ficha se retira.
drop function if exists public.rpc_vincular_cuenta(uuid, text);
create function public.rpc_vincular_cuenta(p_perfil_id uuid, p_correo text)
returns void language plpgsql security definer set search_path = public as $$
declare v_auth uuid; v_otro uuid;
begin
  if not public.fn_conduce() then
    raise exception 'Solo la coordinación o la gerencia pueden vincular cuentas.';
  end if;
  select id into v_auth from auth.users where lower(email) = lower(trim(p_correo));
  if v_auth is null then
    raise exception 'No existe una cuenta de acceso con el correo %.', p_correo;
  end if;
  select id into v_otro from public.perfiles where auth_id = v_auth and id <> p_perfil_id;
  if v_otro is not null then
    if exists (select 1 from public.perfiles where id = v_otro and rol is not null) then
      raise exception 'Esa cuenta ya está vinculada a otra ficha con rol asignado. Revise antes de continuar.';
    end if;
    -- Se libera también el correo: la ficha retirada lo conservaba y chocaba con el índice
    -- de correo único al pasarlo a la ficha correcta (fallo encontrado por la prueba 5).
    update public.perfiles set auth_id = null, activo = false, correo = null,
           retirado_motivo = 'Ficha automática reemplazada al vincular la cuenta ' || lower(trim(p_correo))
    where id = v_otro;
  end if;
  update public.perfiles set auth_id = v_auth, correo = coalesce(correo, lower(trim(p_correo)))
  where id = p_perfil_id;
  if not found then raise exception 'La ficha indicada no existe.'; end if;
end $$;

-- Marca un aviso como leído (solo los propios).
drop function if exists public.rpc_marcar_leida(bigint);
create function public.rpc_marcar_leida(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.notificaciones set leida_en = coalesce(leida_en, now())
  where id = p_id and destinatario_id = public.fn_mi_perfil_id();
end $$;

-- Paso de modo prueba a operación real (o al revés). Queda en bitácora.
drop function if exists public.rpc_cambiar_modo(text, text);
create function public.rpc_cambiar_modo(p_modo text, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare v_antes text;
begin
  if not public.fn_es_admin() then
    raise exception 'Solo un administrador puede cambiar el modo del sistema.';
  end if;
  if p_modo not in ('prueba', 'operacion') then raise exception 'Modo no válido.'; end if;
  if p_motivo is null or length(trim(p_motivo)) < 3 then raise exception 'Indique el motivo del cambio.'; end if;
  select modo into v_antes from public.sistema_config where id;
  if v_antes = p_modo then return; end if;
  update public.sistema_config set modo = p_modo, actualizado_en = now() where id;
  insert into public.modo_bitacora (modo_antes, modo_nuevo, motivo, perfil_id)
  values (v_antes, p_modo, trim(p_motivo), public.fn_mi_perfil_id());
end $$;

-- -----------------------------------------------------------------------------
-- Seguridad a nivel de fila
--   Ninguna tabla se escribe directamente desde la aplicación: toda escritura pasa por una
--   función rpc_* que valida permisos. Por eso solo hay políticas de lectura.
-- -----------------------------------------------------------------------------
alter table public.sistema_config  enable row level security;
alter table public.modo_bitacora   enable row level security;
alter table public.perfiles        enable row level security;
alter table public.notificaciones  enable row level security;
alter table public.auditoria       enable row level security;

revoke all on public.sistema_config, public.modo_bitacora, public.perfiles,
              public.notificaciones, public.auditoria from anon, authenticated;
grant select on public.sistema_config, public.modo_bitacora, public.perfiles,
                public.notificaciones, public.auditoria to authenticated;
revoke all on all sequences in schema public from anon, authenticated;

drop policy if exists p_config_ver on public.sistema_config;
create policy p_config_ver on public.sistema_config for select to authenticated
  using (public.fn_mi_rol() is not null);

drop policy if exists p_modo_bitacora_ver on public.modo_bitacora;
create policy p_modo_bitacora_ver on public.modo_bitacora for select to authenticated
  using (public.fn_ve_todo());

-- El directorio de personal lo ve cualquiera con rol asignado (hace falta para asignar trabajo).
drop policy if exists p_perfiles_ver on public.perfiles;
create policy p_perfiles_ver on public.perfiles for select to authenticated
  using (public.fn_mi_rol() is not null or auth_id = auth.uid());

drop policy if exists p_notificaciones_ver on public.notificaciones;
create policy p_notificaciones_ver on public.notificaciones for select to authenticated
  using (destinatario_id = public.fn_mi_perfil_id());

-- Política RESTRICTIVA: separa por completo lo de prácticas de lo de operación real.
drop policy if exists p_modo_notificaciones on public.notificaciones;
create policy p_modo_notificaciones on public.notificaciones as restrictive for select to authenticated
  using (es_prueba = public.fn_modo_prueba());

drop policy if exists p_auditoria_ver on public.auditoria;
create policy p_auditoria_ver on public.auditoria for select to authenticated
  using (public.fn_ve_todo());

-- -----------------------------------------------------------------------------
-- Permisos explícitos por función (PostgreSQL concede EXECUTE a PUBLIC por omisión,
-- y Supabase además a anon y authenticated)
-- -----------------------------------------------------------------------------
-- Funciones de uso interno: nadie las llama desde la aplicación
revoke all on function public.fn_avisar(uuid[], text, text, text, text) from public, anon, authenticated;
revoke all on function public.trg_auditar()        from public, anon, authenticated;
revoke all on function public.trg_actualizado_en() from public, anon, authenticated;
revoke all on function public.trg_nuevo_usuario()  from public, anon, authenticated;

-- Llaves (las usan las políticas) y funciones de la aplicación
do $$
declare f text;
begin
  foreach f in array array[
    'public.fn_modo_prueba()', 'public.fn_mi_perfil_id()', 'public.fn_mi_rol()',
    'public.fn_conduce()', 'public.fn_ve_todo()', 'public.fn_es_admin()',
    'public.rpc_mi_sesion()',
    'public.rpc_personal_guardar(uuid, text, text, public.rol_usuario, text, text, text, text)',
    'public.rpc_personal_retirar(uuid, text)', 'public.rpc_vincular_cuenta(uuid, text)',
    'public.rpc_marcar_leida(bigint)', 'public.rpc_cambiar_modo(text, text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 8. Comprobaciones. Si una falla, el archivo entero se revierte.
-- -----------------------------------------------------------------------------
set local client_min_messages = notice;
do $$
declare r record; n int;
begin
  -- a) Toda tabla de public tiene RLS activo
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity loop
    raise exception 'La tabla % no tiene seguridad a nivel de fila activa.', r.relname;
  end loop;

  -- b) anon no lee ni escribe ninguna tabla
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind = 'r'
             and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('anon', c.oid, 'INSERT')
               or has_table_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE')) loop
    raise exception 'El rol anon tiene acceso a la tabla %.', r.relname;
  end loop;

  -- c) authenticated no escribe directamente en ninguna tabla
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind = 'r'
             and (has_table_privilege('authenticated', c.oid, 'INSERT') or has_table_privilege('authenticated', c.oid, 'UPDATE')
               or has_table_privilege('authenticated', c.oid, 'DELETE')) loop
    raise exception 'El rol authenticated puede escribir directamente en la tabla %.', r.relname;
  end loop;

  -- d) Ninguna función del sistema la ejecuta anon
  for r in select p.oid::regprocedure as f from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and p.proname !~ '^banco_'
             and has_function_privilege('anon', p.oid, 'EXECUTE') loop
    raise exception 'La función % la puede ejecutar anon.', r.f;
  end loop;

  -- e) Toda función security definer fija su search_path
  for r in select p.oid::regprocedure as f from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and p.prosecdef
             and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%') loop
    raise exception 'La función % es security definer y no fija search_path.', r.f;
  end loop;

  -- f) Ninguna función quedó duplicada con otra firma
  for r in select p.proname, count(*) c from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' group by p.proname having count(*) > 1 loop
    raise exception 'La función % existe con % firmas distintas.', r.proname, r.c;
  end loop;

  select count(*) into n from pg_class c join pg_namespace s on s.oid = c.relnamespace
  where s.nspname = 'public' and c.relkind = 'r';
  raise notice 'OK · versión de esquema %, modo %', (select version_esquema from public.sistema_config),
                                                    (select modo from public.sistema_config);
  raise notice 'OK · % tablas, todas con RLS; anon sin acceso; escritura solo por funciones rpc', n;
  raise notice 'OK · % políticas, % funciones del sistema',
    (select count(*) from pg_policies where schemaname = 'public'),
    (select count(*) from pg_proc p join pg_namespace s on s.oid = p.pronamespace
     where s.nspname = 'public' and p.proname !~ '^banco_');
end $$;

-- Resumen visible en el editor SQL de Supabase (que no muestra los avisos NOTICE).
select 'versión de esquema' as comprobacion, version_esquema || ' · modo ' || modo as resultado
from public.sistema_config
union all
select 'tablas con RLS', count(*) filter (where c.relrowsecurity) || ' de ' || count(*)
from pg_class c join pg_namespace s on s.oid = c.relnamespace
where s.nspname = 'public' and c.relkind = 'r'
union all
select 'políticas', count(*)::text from pg_policies where schemaname = 'public'
union all
select 'funciones que anon puede ejecutar', count(*)::text
from pg_proc p join pg_namespace s on s.oid = p.pronamespace
where s.nspname = 'public' and p.proname !~ '^banco_' and has_function_privilege('anon', p.oid, 'EXECUTE');
