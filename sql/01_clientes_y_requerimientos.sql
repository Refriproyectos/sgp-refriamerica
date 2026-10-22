-- =============================================================================
-- SGP · 01_clientes_y_requerimientos.sql — versión de esquema 0.2
--
-- Proceso PRY-01 (RFA-PRY-MAN-001) · Formato RFA-PRY-FOR-001 Ficha de requerimiento,
-- aprobado el 22/10/2026.
--
-- Qué crea:
--   1. Catálogo de clientes propio de Proyectos (código CLI-NNNN, RIF validado)
--   2. Requerimientos con código PRY-AA-NNNN que se reinicia cada año
--      (en modo prueba: PRB-AA-NNNN, con su propia numeración, para no consumir la real)
--   3. Estados con transiciones controladas e historial de cada cambio
--   4. Asignación (modalidad, ingeniero) con avisos al ingeniero y al vendedor
--   5. Permisos: cada quien ve lo suyo; la conducción ve todo
--
-- Requiere 00_base_comun.sql. Se puede volver a ejecutar.
-- ADVERTENCIA: 00_base_comun.sql retira TODAS las políticas al inicio. Si alguna vez se
-- vuelve a ejecutar el 00, hay que ejecutar después este 01 (y los siguientes).
-- =============================================================================
set local client_min_messages = warning;

-- Para volver a ejecutar: las políticas de este archivo dependen de sus funciones.
-- (En la primera ejecución las tablas aún no existen: se revisa antes de retirar.)
do $$
declare r record;
begin
  for r in select tablename, policyname from pg_policies
           where schemaname = 'public' and tablename in ('clientes', 'requerimientos', 'requerimiento_estados') loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 1. Clientes
-- -----------------------------------------------------------------------------
create sequence if not exists public.seq_cliente;

create table if not exists public.clientes (
  id                 uuid primary key default gen_random_uuid(),
  codigo             text not null unique default ('CLI-' || lpad(nextval('public.seq_cliente')::text, 4, '0')),
  razon_social       text not null check (length(trim(razon_social)) > 1),
  nombre_comercial   text,
  rif                text check (rif ~ '^[JGVEPC]-[0-9]{8}-[0-9]$'),
  tipo               text not null default 'privado' check (tipo in ('privado', 'publico', 'militar', 'residencial')),
  direccion_fiscal   text,
  contacto_nombre    text,
  contacto_cargo     text,
  contacto_telefono  text,
  contacto_correo    text,
  activo             boolean not null default true,
  creado_por         uuid references public.perfiles (id),
  creado_en          timestamptz not null default now(),
  actualizado_en     timestamptz not null default now()
);
create unique index if not exists clientes_rif_unico on public.clientes (rif) where rif is not null;
create index if not exists clientes_razon on public.clientes (lower(razon_social));

-- -----------------------------------------------------------------------------
-- 2. Requerimientos
-- -----------------------------------------------------------------------------
-- Correlativo por año y por modo. Una fila por (año, modo): el insert ... on conflict es
-- atómico, así que dos registros simultáneos nunca reciben el mismo número.
create table if not exists public.correlativos_proyecto (
  anio      smallint not null,
  prueba    boolean  not null,
  ultimo    integer  not null default 0,
  primary key (anio, prueba)
);

create table if not exists public.requerimientos (
  id                       uuid primary key default gen_random_uuid(),
  codigo                   text not null unique,
  -- Origen
  vendedor_id              uuid not null references public.perfiles (id),
  canal                    text check (canal in ('visita', 'llamada', 'correo', 'whatsapp', 'licitacion', 'referido')),
  -- Cliente
  cliente_id               uuid not null references public.clientes (id),
  contacto_nombre          text,
  contacto_cargo           text,
  contacto_telefono        text,
  contacto_correo          text,
  -- Obra / sitio
  obra_nombre              text not null check (length(trim(obra_nombre)) > 1),
  direccion                text not null check (length(trim(direccion)) > 2),
  estado_geo               text not null check (estado_geo in (
                             'Amazonas', 'Anzoátegui', 'Apure', 'Aragua', 'Barinas', 'Bolívar', 'Carabobo',
                             'Cojedes', 'Delta Amacuro', 'Distrito Capital', 'Falcón', 'Guárico', 'La Guaira',
                             'Lara', 'Mérida', 'Miranda', 'Monagas', 'Nueva Esparta', 'Portuguesa', 'Sucre',
                             'Táchira', 'Trujillo', 'Yaracuy', 'Zulia', 'Dependencias Federales')),
  ciudad                   text not null check (length(trim(ciudad)) > 1),
  tipo_edificacion         text check (tipo_edificacion in ('residencial', 'comercial', 'oficinas', 'industrial',
                             'salud', 'educativo', 'gubernamental_militar', 'otro')),
  area_m2                  numeric(12, 2) check (area_m2 > 0),
  niveles                  smallint check (niveles > 0),
  contacto_sitio           text,
  -- Alcance
  tipo_solicitud           text not null check (tipo_solicitud in ('sistema_nuevo', 'ampliacion', 'reemplazo', 'adecuacion', 'diagnostico')),
  sistemas                 text[] not null default '{}' check (sistemas <@ array['expansion_directa', 'vrf', 'agua_helada',
                             'uma', 'ventilacion_extraccion', 'presurizacion', 'controles_bms', 'otro']),
  descripcion              text not null check (length(trim(descripcion)) > 4),
  info_recibida            text[] not null default '{}' check (info_recibida <@ array['planos', 'fotos', 'especificaciones', 'ninguna']),
  requiere_levantamiento   boolean,
  -- Plazos
  fecha_requerida          date,
  prioridad                text not null default 'normal' check (prioridad in ('normal', 'alta', 'urgente')),
  presupuesto_estimado_usd numeric(14, 2) check (presupuesto_estimado_usd >= 0),
  -- Clasificación (Coordinador, PRY-01)
  modalidad                char(1) check (modalidad in ('A', 'B', 'C', 'D')),
  ingeniero_id             uuid references public.perfiles (id),
  disciplinas              text[] not null default '{}' check (disciplinas <@ array['HV', 'AU']),
  fecha_compromiso         date,
  observaciones            text,
  -- Estado
  estado                   text not null default 'registrado' check (estado in ('registrado', 'asignado', 'en_levantamiento',
                             'en_ingenieria', 'enviado_ventas', 'aprobado', 'en_espera', 'rechazado', 'cerrado')),
  motivo_estado            text,
  -- Trazabilidad
  registrado_por           uuid references public.perfiles (id),
  registrado_en            timestamptz not null default now(),
  actualizado_en           timestamptz not null default now(),
  es_prueba                boolean not null default public.fn_modo_prueba(),
  -- Un requerimiento asignado siempre tiene modalidad e ingeniero
  constraint requerimientos_asignacion_completa check (
    estado = 'registrado' or (modalidad is not null and ingeniero_id is not null))
);
create index if not exists requerimientos_estado on public.requerimientos (estado);
create index if not exists requerimientos_vendedor on public.requerimientos (vendedor_id);
create index if not exists requerimientos_ingeniero on public.requerimientos (ingeniero_id);
create index if not exists requerimientos_cliente on public.requerimientos (cliente_id);

create table if not exists public.requerimiento_estados (
  id                bigint generated always as identity primary key,
  requerimiento_id  uuid not null references public.requerimientos (id) on delete cascade,
  estado_antes      text,
  estado_nuevo      text not null,
  motivo            text,
  perfil_id         uuid references public.perfiles (id),
  en                timestamptz not null default now()
);
create index if not exists req_estados_req on public.requerimiento_estados (requerimiento_id, en);

-- -----------------------------------------------------------------------------
-- 3. Funciones internas
-- -----------------------------------------------------------------------------
drop function if exists public.fn_siguiente_codigo_proyecto();
create function public.fn_siguiente_codigo_proyecto() returns text
language plpgsql security definer set search_path = public as $$
declare
  v_anio   smallint := extract(year from (now() at time zone 'America/Caracas'))::smallint;
  v_prueba boolean  := public.fn_modo_prueba();
  v_n      integer;
begin
  insert into public.correlativos_proyecto (anio, prueba, ultimo) values (v_anio, v_prueba, 1)
  on conflict (anio, prueba) do update set ultimo = correlativos_proyecto.ultimo + 1
  returning ultimo into v_n;
  if v_n > 9999 then
    raise exception 'Se agotó la numeración de proyectos del año %.', v_anio;
  end if;
  return (case when v_prueba then 'PRB-' else 'PRY-' end)
         || to_char(v_anio % 100, 'FM00') || '-' || to_char(v_n, 'FM0000');
end $$;

-- ¿Puede la persona en sesión ver este requerimiento? (usada por la política del historial)
-- «create or replace» (sin retirarla antes): la usan políticas de archivos posteriores (02).
create or replace function public.fn_puede_ver_requerimiento(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.requerimientos r
    where r.id = p_id and r.es_prueba = public.fn_modo_prueba()
      and (public.fn_ve_todo() or r.vendedor_id = public.fn_mi_perfil_id() or r.ingeniero_id = public.fn_mi_perfil_id()))
$$;

-- Perfiles de la conducción que reciben los avisos de nuevos requerimientos
drop function if exists public.fn_perfiles_conduccion();
create function public.fn_perfiles_conduccion() returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(id), '{}') from public.perfiles
  where activo and rol in ('coordinador', 'gerente')
$$;

drop function if exists public.fn_nombre_estado(text);
create function public.fn_nombre_estado(p text) returns text
language sql immutable as $$
  select case p
    when 'registrado' then 'Registrado' when 'asignado' then 'Asignado'
    when 'en_levantamiento' then 'En levantamiento' when 'en_ingenieria' then 'En ingeniería'
    when 'enviado_ventas' then 'Enviado a Ventas' when 'aprobado' then 'Aprobado'
    when 'en_espera' then 'En espera' when 'rechazado' then 'Rechazado' when 'cerrado' then 'Cerrado'
    else p end
$$;

-- -----------------------------------------------------------------------------
-- 4. Disparadores
-- -----------------------------------------------------------------------------
drop trigger if exists trg_auditar_clientes on public.clientes;
create trigger trg_auditar_clientes after insert or update or delete on public.clientes
for each row execute function public.trg_auditar();
drop trigger if exists trg_auditar_requerimientos on public.requerimientos;
create trigger trg_auditar_requerimientos after insert or update or delete on public.requerimientos
for each row execute function public.trg_auditar();
drop trigger if exists trg_clientes_actualizado on public.clientes;
create trigger trg_clientes_actualizado before update on public.clientes
for each row execute function public.trg_actualizado_en();
drop trigger if exists trg_requerimientos_actualizado on public.requerimientos;
create trigger trg_requerimientos_actualizado before update on public.requerimientos
for each row execute function public.trg_actualizado_en();

-- -----------------------------------------------------------------------------
-- 5. Funciones que llama la aplicación
-- -----------------------------------------------------------------------------

-- Alta o edición de un cliente (conducción y Ventas)
drop function if exists public.rpc_cliente_guardar(uuid, jsonb);
create function public.rpc_cliente_guardar(p_id uuid, p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.clientes; v_rif text;
begin
  if not (public.fn_conduce() or public.fn_mi_rol() = 'ventas') then
    raise exception 'Solo la coordinación, la gerencia o Ventas pueden registrar clientes.';
  end if;
  if coalesce(length(trim(p ->> 'razon_social')), 0) < 2 then
    raise exception 'La razón social es obligatoria.';
  end if;
  v_rif := nullif(upper(regexp_replace(coalesce(p ->> 'rif', ''), '\s', '', 'g')), '');
  if v_rif is not null and v_rif !~ '^[JGVEPC]-[0-9]{8}-[0-9]$' then
    raise exception 'El RIF debe tener el formato J-12345678-9.';
  end if;
  if v_rif is not null and exists (select 1 from public.clientes where rif = v_rif and id is distinct from p_id) then
    raise exception 'Ya existe un cliente con el RIF %.', v_rif;
  end if;

  if p_id is null then
    insert into public.clientes (razon_social, nombre_comercial, rif, tipo, direccion_fiscal,
                                 contacto_nombre, contacto_cargo, contacto_telefono, contacto_correo, creado_por)
    values (trim(p ->> 'razon_social'), nullif(trim(p ->> 'nombre_comercial'), ''), v_rif,
            coalesce(nullif(p ->> 'tipo', ''), 'privado'), nullif(trim(p ->> 'direccion_fiscal'), ''),
            nullif(trim(p ->> 'contacto_nombre'), ''), nullif(trim(p ->> 'contacto_cargo'), ''),
            nullif(trim(p ->> 'contacto_telefono'), ''), nullif(trim(p ->> 'contacto_correo'), ''),
            public.fn_mi_perfil_id())
    returning * into v;
  else
    update public.clientes set
      razon_social = trim(p ->> 'razon_social'), nombre_comercial = nullif(trim(p ->> 'nombre_comercial'), ''),
      rif = v_rif, tipo = coalesce(nullif(p ->> 'tipo', ''), tipo),
      direccion_fiscal = nullif(trim(p ->> 'direccion_fiscal'), ''),
      contacto_nombre = nullif(trim(p ->> 'contacto_nombre'), ''), contacto_cargo = nullif(trim(p ->> 'contacto_cargo'), ''),
      contacto_telefono = nullif(trim(p ->> 'contacto_telefono'), ''), contacto_correo = nullif(trim(p ->> 'contacto_correo'), '')
    where id = p_id returning * into v;
    if not found then raise exception 'El cliente indicado no existe.'; end if;
  end if;
  return jsonb_build_object('id', v.id, 'codigo', v.codigo);
end $$;

-- Registro de un requerimiento (PRY-01). Ventas registra a su nombre; la conducción elige
-- al vendedor (que puede estar en Personal sin cuenta de acceso).
drop function if exists public.rpc_requerimiento_registrar(jsonb);
create function public.rpc_requerimiento_registrar(p jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_vendedor uuid; v public.requerimientos; v_cliente text;
begin
  if public.fn_conduce() then
    v_vendedor := nullif(p ->> 'vendedor_id', '')::uuid;
    if v_vendedor is null then raise exception 'Indique el vendedor responsable.'; end if;
    if not exists (select 1 from public.perfiles where id = v_vendedor and activo and rol = 'ventas') then
      raise exception 'El vendedor indicado no está activo con rol de Ventas.';
    end if;
  elsif public.fn_mi_rol() = 'ventas' then
    v_vendedor := public.fn_mi_perfil_id();
  else
    raise exception 'Solo Ventas o la coordinación pueden registrar requerimientos.';
  end if;

  if not exists (select 1 from public.clientes where id = nullif(p ->> 'cliente_id', '')::uuid and activo) then
    raise exception 'Seleccione un cliente del catálogo.';
  end if;

  insert into public.requerimientos (
    codigo, vendedor_id, canal, cliente_id, contacto_nombre, contacto_cargo, contacto_telefono, contacto_correo,
    obra_nombre, direccion, estado_geo, ciudad, tipo_edificacion, area_m2, niveles, contacto_sitio,
    tipo_solicitud, sistemas, descripcion, info_recibida, requiere_levantamiento,
    fecha_requerida, prioridad, presupuesto_estimado_usd, registrado_por)
  values (
    public.fn_siguiente_codigo_proyecto(), v_vendedor, nullif(p ->> 'canal', ''), (p ->> 'cliente_id')::uuid,
    nullif(trim(p ->> 'contacto_nombre'), ''), nullif(trim(p ->> 'contacto_cargo'), ''),
    nullif(trim(p ->> 'contacto_telefono'), ''), nullif(trim(p ->> 'contacto_correo'), ''),
    trim(p ->> 'obra_nombre'), trim(p ->> 'direccion'), p ->> 'estado_geo', trim(p ->> 'ciudad'),
    nullif(p ->> 'tipo_edificacion', ''), nullif(p ->> 'area_m2', '')::numeric, nullif(p ->> 'niveles', '')::smallint,
    nullif(trim(p ->> 'contacto_sitio'), ''),
    p ->> 'tipo_solicitud',
    coalesce((select array_agg(x) from jsonb_array_elements_text(p -> 'sistemas') x), '{}'),
    trim(p ->> 'descripcion'),
    coalesce((select array_agg(x) from jsonb_array_elements_text(p -> 'info_recibida') x), '{}'),
    (p ->> 'requiere_levantamiento')::boolean,
    nullif(p ->> 'fecha_requerida', '')::date, coalesce(nullif(p ->> 'prioridad', ''), 'normal'),
    nullif(p ->> 'presupuesto_estimado_usd', '')::numeric, public.fn_mi_perfil_id())
  returning * into v;

  insert into public.requerimiento_estados (requerimiento_id, estado_antes, estado_nuevo, perfil_id)
  values (v.id, null, 'registrado', public.fn_mi_perfil_id());

  select razon_social into v_cliente from public.clientes where id = v.cliente_id;
  perform public.fn_avisar(public.fn_perfiles_conduccion(), 'requerimiento_nuevo',
    'Nuevo requerimiento ' || v.codigo, v_cliente || ' · ' || v.obra_nombre, '#/requerimientos/' || v.id);
  return jsonb_build_object('id', v.id, 'codigo', v.codigo);
exception
  when check_violation or not_null_violation then
    raise exception 'Revise los datos: hay un campo obligatorio vacío o un valor fuera de la lista (%).', sqlerrm;
  when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then
    raise exception 'Revise los datos: hay un número o una fecha con formato inválido.';
end $$;

-- Clasificación y asignación (solo la conducción)
drop function if exists public.rpc_requerimiento_asignar(uuid, char, uuid, text[], date, text);
create function public.rpc_requerimiento_asignar(p_id uuid, p_modalidad char, p_ingeniero uuid,
                                                p_disciplinas text[], p_fecha_compromiso date, p_observaciones text)
returns void language plpgsql security definer set search_path = public as $$
declare r public.requerimientos; v_antes uuid;
begin
  if not public.fn_conduce() then
    raise exception 'Solo la coordinación o la gerencia asignan requerimientos.';
  end if;
  select * into r from public.requerimientos where id = p_id and es_prueba = public.fn_modo_prueba() for update;
  if not found then raise exception 'El requerimiento indicado no existe.'; end if;
  if r.estado not in ('registrado', 'asignado', 'en_levantamiento', 'en_ingenieria') then
    raise exception 'No se puede reasignar un requerimiento en estado %.', public.fn_nombre_estado(r.estado);
  end if;
  if p_modalidad is null or p_modalidad not in ('A', 'B', 'C', 'D') then
    raise exception 'Indique la modalidad (A, B, C o D).';
  end if;
  if not exists (select 1 from public.perfiles where id = p_ingeniero and activo and rol in ('ingeniero', 'coordinador')) then
    raise exception 'El responsable debe ser un ingeniero o coordinador activo.';
  end if;
  v_antes := r.ingeniero_id;
  update public.requerimientos set modalidad = p_modalidad, ingeniero_id = p_ingeniero,
         disciplinas = coalesce(p_disciplinas, '{}'), fecha_compromiso = p_fecha_compromiso,
         observaciones = nullif(trim(p_observaciones), ''),
         estado = case when estado = 'registrado' then 'asignado' else estado end
  where id = p_id;
  if r.estado = 'registrado' then
    insert into public.requerimiento_estados (requerimiento_id, estado_antes, estado_nuevo, motivo, perfil_id)
    values (p_id, 'registrado', 'asignado', 'Modalidad ' || p_modalidad, public.fn_mi_perfil_id());
  end if;
  if v_antes is distinct from p_ingeniero then
    perform public.fn_avisar(array[p_ingeniero], 'requerimiento_asignado',
      'Se le asignó ' || r.codigo, r.obra_nombre || coalesce(' · entrega ' || to_char(p_fecha_compromiso, 'DD/MM/YYYY'), ''),
      '#/requerimientos/' || p_id);
  end if;
  perform public.fn_avisar(array[r.vendedor_id], 'requerimiento_asignado',
    r.codigo || ' asignado', 'Modalidad ' || p_modalidad, '#/requerimientos/' || p_id);
end $$;

-- Cambio de estado con reglas por rol
drop function if exists public.rpc_requerimiento_estado(uuid, text, text);
create function public.rpc_requerimiento_estado(p_id uuid, p_nuevo text, p_motivo text)
returns void language plpgsql security definer set search_path = public as $$
declare r public.requerimientos; v_yo uuid := public.fn_mi_perfil_id(); v_ok boolean := false;
begin
  select * into r from public.requerimientos where id = p_id and es_prueba = public.fn_modo_prueba() for update;
  if not found then raise exception 'El requerimiento indicado no existe.'; end if;
  if p_nuevo = r.estado then return; end if;

  -- Transiciones válidas
  v_ok := (r.estado, p_nuevo) in (
      ('asignado', 'en_levantamiento'), ('asignado', 'en_ingenieria'),
      ('en_levantamiento', 'en_ingenieria'),
      ('en_ingenieria', 'enviado_ventas'),
      ('enviado_ventas', 'aprobado'), ('enviado_ventas', 'en_espera'), ('enviado_ventas', 'rechazado'),
      ('en_espera', 'enviado_ventas'), ('en_espera', 'aprobado'), ('en_espera', 'rechazado'),
      ('aprobado', 'cerrado'), ('rechazado', 'cerrado'))
    -- Modalidad A (apoyo técnico): termina al entregar la nota técnica, sin pasar por Ventas
    or (r.modalidad = 'A' and p_nuevo = 'cerrado' and r.estado in ('asignado', 'en_levantamiento', 'en_ingenieria'));
  if not v_ok then
    raise exception 'No se puede pasar de % a %.', public.fn_nombre_estado(r.estado), public.fn_nombre_estado(p_nuevo);
  end if;

  -- Quién puede
  if not public.fn_conduce() then
    if p_nuevo in ('en_levantamiento', 'en_ingenieria', 'enviado_ventas') or (p_nuevo = 'cerrado' and r.modalidad = 'A') then
      if r.ingeniero_id is distinct from v_yo then
        raise exception 'Solo el ingeniero asignado o la coordinación pueden hacer este cambio.';
      end if;
    elsif p_nuevo in ('aprobado', 'en_espera', 'rechazado') then
      if r.vendedor_id is distinct from v_yo then
        raise exception 'Solo el vendedor responsable o la coordinación registran la decisión del cliente.';
      end if;
    else
      raise exception 'Solo la coordinación puede cerrar el requerimiento.';
    end if;
  end if;

  if p_nuevo in ('rechazado', 'en_espera') and coalesce(length(trim(p_motivo)), 0) < 3 then
    raise exception 'Indique el motivo.';
  end if;

  update public.requerimientos set estado = p_nuevo, motivo_estado = nullif(trim(p_motivo), '') where id = p_id;
  insert into public.requerimiento_estados (requerimiento_id, estado_antes, estado_nuevo, motivo, perfil_id)
  values (p_id, r.estado, p_nuevo, nullif(trim(p_motivo), ''), v_yo);

  perform public.fn_avisar(
    array(select x from unnest(array[r.vendedor_id, r.ingeniero_id] || public.fn_perfiles_conduccion()) x
          where x is distinct from v_yo),
    'requerimiento_estado', r.codigo || ': ' || public.fn_nombre_estado(p_nuevo),
    coalesce(nullif(trim(p_motivo), ''), r.obra_nombre), '#/requerimientos/' || p_id);
end $$;

-- -----------------------------------------------------------------------------
-- Seguridad a nivel de fila
-- -----------------------------------------------------------------------------
alter table public.clientes enable row level security;
alter table public.correlativos_proyecto enable row level security;
alter table public.requerimientos enable row level security;
alter table public.requerimiento_estados enable row level security;

revoke all on public.clientes, public.correlativos_proyecto, public.requerimientos,
              public.requerimiento_estados from anon, authenticated;
grant select on public.clientes, public.requerimientos, public.requerimiento_estados to authenticated;
revoke all on all sequences in schema public from anon, authenticated;

create policy p_clientes_ver on public.clientes for select to authenticated
  using (public.fn_mi_rol() is not null);

create policy p_requerimientos_ver on public.requerimientos for select to authenticated
  using (public.fn_ve_todo() or vendedor_id = public.fn_mi_perfil_id() or ingeniero_id = public.fn_mi_perfil_id());

create policy p_modo_requerimientos on public.requerimientos as restrictive for select to authenticated
  using (es_prueba = public.fn_modo_prueba());

create policy p_req_estados_ver on public.requerimiento_estados for select to authenticated
  using (public.fn_puede_ver_requerimiento(requerimiento_id));

-- Permisos explícitos por función
revoke all on function public.fn_siguiente_codigo_proyecto() from public, anon, authenticated;
revoke all on function public.fn_perfiles_conduccion()       from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    'public.fn_puede_ver_requerimiento(uuid)', 'public.fn_nombre_estado(text)',
    'public.rpc_cliente_guardar(uuid, jsonb)', 'public.rpc_requerimiento_registrar(jsonb)',
    'public.rpc_requerimiento_asignar(uuid, char, uuid, text[], date, text)',
    'public.rpc_requerimiento_estado(uuid, text, text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- No retrocede la versión si ya se ejecutaron archivos posteriores
update public.sistema_config set version_esquema = '0.2', actualizado_en = now() where id and version_esquema < '0.2';

-- -----------------------------------------------------------------------------
-- Comprobaciones (las mismas reglas del 00, sobre todo el esquema)
-- -----------------------------------------------------------------------------
set local client_min_messages = notice;
do $$
declare r record;
begin
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity loop
    raise exception 'La tabla % no tiene seguridad a nivel de fila activa.', r.relname;
  end loop;
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind = 'r'
             and (has_table_privilege('anon', c.oid, 'SELECT') or has_table_privilege('anon', c.oid, 'INSERT')
               or has_table_privilege('anon', c.oid, 'UPDATE') or has_table_privilege('anon', c.oid, 'DELETE')) loop
    raise exception 'El rol anon tiene acceso a la tabla %.', r.relname;
  end loop;
  for r in select c.relname from pg_class c join pg_namespace s on s.oid = c.relnamespace
           where s.nspname = 'public' and c.relkind = 'r'
             and (has_table_privilege('authenticated', c.oid, 'INSERT') or has_table_privilege('authenticated', c.oid, 'UPDATE')
               or has_table_privilege('authenticated', c.oid, 'DELETE')) loop
    raise exception 'El rol authenticated puede escribir directamente en la tabla %.', r.relname;
  end loop;
  for r in select p.oid::regprocedure as f from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and p.proname !~ '^banco_' and has_function_privilege('anon', p.oid, 'EXECUTE') loop
    raise exception 'La función % la puede ejecutar anon.', r.f;
  end loop;
  for r in select p.oid::regprocedure as f from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' and p.prosecdef
             and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%') loop
    raise exception 'La función % es security definer y no fija search_path.', r.f;
  end loop;
  for r in select p.proname, count(*) c from pg_proc p join pg_namespace s on s.oid = p.pronamespace
           where s.nspname = 'public' group by p.proname having count(*) > 1 loop
    raise exception 'La función % existe con % firmas distintas.', r.proname, r.c;
  end loop;
  -- Las políticas del 00 deben seguir existiendo
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'perfiles') = 0 then
    raise exception 'Faltan las políticas de perfiles: ejecute primero 00_base_comun.sql.';
  end if;
  raise notice 'OK · versión de esquema 0.2: clientes y requerimientos';
end $$;

-- Resumen visible en el editor SQL de Supabase
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
where s.nspname = 'public' and p.proname !~ '^banco_' and has_function_privilege('anon', p.oid, 'EXECUTE')
union all
select 'clientes · requerimientos', (select count(*) from public.clientes) || ' · ' || (select count(*) from public.requerimientos);
