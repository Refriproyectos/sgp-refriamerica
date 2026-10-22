-- =============================================================================
-- SGP · 02_levantamientos.sql — versión de esquema 0.3
--
-- Proceso PRY-02 (RFA-PRY-MAN-001) · Formato RFA-PRY-FOR-002 Informe de levantamiento
-- de campo, aprobado el 22/10/2026 (tipos: instalación nueva, existente y mixta).
--
-- Qué crea:
--   1. Levantamientos ligados a un requerimiento, con código de documento
--      PRY-AA-NNNN-GE-IL-NNN (en modo prueba, PRB-…). Puede haber varios por requerimiento.
--      Se pueden iniciar sin señal: el código se asigna cuando el teléfono lo registra.
--   2. El contenido del formulario (los 9 pasos) se guarda como un documento JSON con
--      número de versión: el teléfono lo llena sin señal y lo sube completo al recuperarla.
--      Si dos equipos lo modificaron a la vez, la base rechaza la copia vieja.
--   3. Fotografías en Supabase Storage (depósito privado "levantamientos"), con su ficha
--      (sección, referencia, descripción, fecha, GPS) en la tabla levantamiento_fotos.
--   4. Flujo: borrador → en revisión → aprobado | devuelto (→ borrador de nuevo).
--      Aprobado queda bloqueado, fotos incluidas.
--
-- Requiere 00 y 01. Se puede volver a ejecutar.
-- ADVERTENCIA: si se vuelve a ejecutar el 00, hay que ejecutar después el 01 y este 02.
-- =============================================================================
set local client_min_messages = warning;

do $$
declare r record;
begin
  for r in select tablename, policyname from pg_policies
           where schemaname = 'public' and tablename in ('levantamientos', 'levantamiento_fotos', 'levantamiento_estados') loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;
drop policy if exists sgp_lev_fotos_ver      on storage.objects;
drop policy if exists sgp_lev_fotos_subir    on storage.objects;
drop policy if exists sgp_lev_fotos_cambiar  on storage.objects;
drop policy if exists sgp_lev_fotos_borrar   on storage.objects;

-- -----------------------------------------------------------------------------
-- 1. Tablas
-- -----------------------------------------------------------------------------
create table if not exists public.levantamientos (
  id                     uuid primary key default gen_random_uuid(),
  requerimiento_id       uuid not null references public.requerimientos (id),
  numero                 smallint not null check (numero between 1 and 999),
  codigo                 text not null unique,
  tipo                   text not null check (tipo in ('nueva', 'existente', 'mixto')),
  estado                 text not null default 'borrador'
                         check (estado in ('borrador', 'en_revision', 'devuelto', 'aprobado')),
  responsable_id         uuid not null references public.perfiles (id),
  contenido              jsonb not null default '{}'::jsonb check (jsonb_typeof(contenido) = 'object'),
  version                integer not null default 1,
  observaciones_revision text,
  enviado_en             timestamptz,
  aprobado_por           uuid references public.perfiles (id),
  aprobado_en            timestamptz,
  creado_por             uuid references public.perfiles (id),
  creado_en              timestamptz not null default now(),
  actualizado_en         timestamptz not null default now(),
  es_prueba              boolean not null,
  unique (requerimiento_id, numero)
);
create index if not exists lev_req on public.levantamientos (requerimiento_id);
create index if not exists lev_responsable on public.levantamientos (responsable_id, estado);

create table if not exists public.levantamiento_fotos (
  id                uuid primary key,                       -- lo genera el teléfono al tomar la foto
  levantamiento_id  uuid not null references public.levantamientos (id) on delete cascade,
  ruta              text not null unique,                   -- <levantamiento>/<foto>.jpg en el depósito
  seccion           text not null check (seccion in ('visita', 'area', 'equipo', 'facilidades', 'medicion', 'hallazgo')),
  referencia        text,                                   -- id del área, equipo o hallazgo dentro del contenido
  descripcion       text,
  tomada_en         timestamptz not null,
  latitud           numeric(9, 6) check (latitud between -90 and 90),
  longitud          numeric(9, 6) check (longitud between -180 and 180),
  bytes             integer check (bytes between 1 and 5242880),
  ancho             smallint,
  alto              smallint,
  creado_por        uuid references public.perfiles (id),
  creado_en         timestamptz not null default now()
);
create index if not exists lev_fotos_lev on public.levantamiento_fotos (levantamiento_id, tomada_en);

create table if not exists public.levantamiento_estados (
  id                bigint generated always as identity primary key,
  levantamiento_id  uuid not null references public.levantamientos (id) on delete cascade,
  estado_antes      text,
  estado_nuevo      text not null,
  motivo            text,
  perfil_id         uuid references public.perfiles (id),
  en                timestamptz not null default now()
);
create index if not exists lev_estados_lev on public.levantamiento_estados (levantamiento_id, en);

-- -----------------------------------------------------------------------------
-- 2. Funciones internas
-- -----------------------------------------------------------------------------
drop function if exists public.fn_puede_ver_levantamiento(uuid);
create function public.fn_puede_ver_levantamiento(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.levantamientos l
                 where l.id = p_id and public.fn_puede_ver_requerimiento(l.requerimiento_id))
$$;

-- Editar: el responsable o la conducción, solo en borrador o devuelto
drop function if exists public.fn_puede_editar_levantamiento(uuid);
create function public.fn_puede_editar_levantamiento(p_id uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.levantamientos l
                 where l.id = p_id and l.es_prueba = public.fn_modo_prueba()
                   and l.estado in ('borrador', 'devuelto')
                   and (public.fn_conduce() or l.responsable_id = public.fn_mi_perfil_id()))
$$;

-- 'uuid/archivo.jpg' → uuid; cualquier otra cosa → null (las políticas la rechazan)
drop function if exists public.fn_lev_desde_ruta(text);
create function public.fn_lev_desde_ruta(p_ruta text) returns uuid
language sql immutable as $$
  select case when split_part(p_ruta, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(p_ruta, '/', 1)::uuid end
$$;

drop function if exists public.fn_nombre_estado_lev(text);
create function public.fn_nombre_estado_lev(p text) returns text
language sql immutable as $$
  select case p when 'borrador' then 'Borrador' when 'en_revision' then 'En revisión'
                when 'devuelto' then 'Devuelto' when 'aprobado' then 'Aprobado' else p end
$$;

-- Revisión mínima del contenido que llega del teléfono: forma, tamaño y listas acotadas.
-- El detalle de cada campo lo valida la aplicación; aquí se protege la base.
drop function if exists public.fn_lev_validar(jsonb);
create function public.fn_lev_validar(c jsonb) returns void
language plpgsql immutable as $$
declare k text;
begin
  if c is null or jsonb_typeof(c) <> 'object' then
    raise exception 'El contenido del levantamiento no tiene el formato esperado.';
  end if;
  if coalesce(c ->> 'tipo', '') not in ('nueva', 'existente', 'mixto') then
    raise exception 'Indique el tipo de levantamiento (nueva, existente o mixto).';
  end if;
  if pg_column_size(c) > 512000 then
    raise exception 'El levantamiento es demasiado extenso (más de 500 KB de texto).';
  end if;
  foreach k in array array['areas', 'equipos', 'instrumentos', 'hallazgos', 'recomendaciones'] loop
    if c ? k and jsonb_typeof(c -> k) <> 'array' then
      raise exception 'La lista % no tiene el formato esperado.', k;
    end if;
    if c ? k and jsonb_array_length(c -> k) > 200 then
      raise exception 'La lista % tiene más de 200 elementos.', k;
    end if;
  end loop;
end $$;

-- Contenido inicial, tomado del requerimiento (paso 1 y alcance ya llenos)
drop function if exists public.fn_lev_contenido_inicial(uuid, text);
create function public.fn_lev_contenido_inicial(p_req uuid, p_tipo text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'tipo', p_tipo,
    'visita', jsonb_build_object(
      'cliente', c.razon_social, 'rif', c.rif,
      'direccion', r.direccion || ', ' || r.ciudad || ', ' || r.estado_geo,
      'contacto', nullif(concat_ws(' · ', r.contacto_nombre, r.contacto_cargo, r.contacto_telefono), ''),
      'tipo_instalacion', case r.tipo_edificacion
          when 'residencial' then 'Residencial' when 'comercial' then 'Comercial' when 'oficinas' then 'Oficinas'
          when 'industrial' then 'Industrial' when 'salud' then 'Salud' when 'educativo' then 'Educativo'
          when 'gubernamental_militar' then 'Gubernamental / militar' when 'otro' then 'Otro' end,
      'sistemas', (select string_agg(case s
          when 'expansion_directa' then 'Expansión directa' when 'vrf' then 'VRF' when 'agua_helada' then 'Agua helada'
          when 'uma' then 'UMA' when 'ventilacion_extraccion' then 'Ventilación / extracción'
          when 'presurizacion' then 'Presurización' when 'controles_bms' then 'Controles / BMS' else 'Otros' end, ', ')
        from unnest(r.sistemas) s)),
    'alcance', r.descripcion,
    'areas', '[]'::jsonb, 'equipos', '[]'::jsonb, 'instrumentos', '[]'::jsonb,
    'hallazgos', '[]'::jsonb, 'recomendaciones', '[]'::jsonb)
  from public.requerimientos r join public.clientes c on c.id = r.cliente_id
  where r.id = p_req
$$;

-- -----------------------------------------------------------------------------
-- 3. Funciones de la aplicación
-- -----------------------------------------------------------------------------
-- Iniciar un levantamiento. El teléfono lo puede iniciar SIN señal: genera el id y el
-- contenido, y lo registra aquí al recuperar la conexión; en ese momento recibe el código.
-- Reintentar con el mismo id no crea otro (devuelve el ya registrado).
drop function if exists public.rpc_levantamiento_crear(uuid);
drop function if exists public.rpc_levantamiento_crear(uuid, uuid, jsonb);
create function public.rpc_levantamiento_crear(p_id uuid, p_requerimiento uuid, p_contenido jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare r public.requerimientos; l public.levantamientos; v_n smallint; v_tipo text; v_codigo text;
        v_contenido jsonb; v_yo uuid := public.fn_mi_perfil_id();
begin
  select * into l from public.levantamientos where id = p_id;
  if found then
    if l.requerimiento_id <> p_requerimiento or not public.fn_puede_ver_levantamiento(p_id) then
      raise exception 'El identificador del levantamiento ya está en uso.';
    end if;
    return jsonb_build_object('id', l.id, 'codigo', l.codigo, 'version', l.version);
  end if;
  select * into r from public.requerimientos
  where id = p_requerimiento and es_prueba = public.fn_modo_prueba() for update;
  if not found then raise exception 'El requerimiento indicado no existe.'; end if;
  if not (public.fn_conduce() or r.ingeniero_id = v_yo) then
    raise exception 'Solo el ingeniero asignado o la coordinación inician un levantamiento.';
  end if;
  if r.estado not in ('asignado', 'en_levantamiento', 'en_ingenieria') then
    raise exception 'No se puede iniciar un levantamiento con el requerimiento en estado %.', public.fn_nombre_estado(r.estado);
  end if;
  v_tipo := case r.tipo_solicitud when 'sistema_nuevo' then 'nueva' when 'diagnostico' then 'existente' else 'mixto' end;
  v_contenido := coalesce(p_contenido, public.fn_lev_contenido_inicial(r.id, v_tipo));
  perform public.fn_lev_validar(v_contenido);
  v_n := coalesce((select max(numero) from public.levantamientos where requerimiento_id = r.id), 0) + 1;
  v_codigo := r.codigo || '-GE-IL-' || lpad(v_n::text, 3, '0');

  insert into public.levantamientos (id, requerimiento_id, numero, codigo, tipo, responsable_id, contenido, creado_por, es_prueba)
  values (coalesce(p_id, gen_random_uuid()), r.id, v_n, v_codigo, v_contenido ->> 'tipo', r.ingeniero_id, v_contenido, v_yo, r.es_prueba)
  returning * into l;
  insert into public.levantamiento_estados (levantamiento_id, estado_nuevo, perfil_id) values (l.id, 'borrador', v_yo);

  if r.estado = 'asignado' then
    update public.requerimientos set estado = 'en_levantamiento' where id = r.id;
    insert into public.requerimiento_estados (requerimiento_id, estado_antes, estado_nuevo, motivo, perfil_id)
    values (r.id, 'asignado', 'en_levantamiento', 'Levantamiento ' || v_codigo || ' iniciado', v_yo);
  end if;
  return jsonb_build_object('id', l.id, 'codigo', l.codigo, 'version', l.version);
end $$;

-- Guardar el contenido completo. p_version = la versión que el equipo tenía al editar;
-- si la base ya tiene otra, se rechaza (CONFLICTO). Con p_version nulo se sobrescribe:
-- la aplicación solo lo usa cuando la persona elige conservar su copia.
drop function if exists public.rpc_levantamiento_guardar(uuid, jsonb, integer);
create function public.rpc_levantamiento_guardar(p_id uuid, p_contenido jsonb, p_version integer)
returns integer language plpgsql security definer set search_path = public as $$
declare l public.levantamientos;
begin
  select * into l from public.levantamientos where id = p_id and es_prueba = public.fn_modo_prueba() for update;
  if not found then raise exception 'El levantamiento indicado no existe.'; end if;
  if not public.fn_puede_editar_levantamiento(p_id) then
    if l.estado in ('en_revision', 'aprobado') then
      raise exception 'El levantamiento está %: ya no se puede modificar.', lower(public.fn_nombre_estado_lev(l.estado));
    end if;
    raise exception 'Solo el responsable o la coordinación modifican este levantamiento.';
  end if;
  if p_version is not null and p_version <> l.version then
    raise exception 'CONFLICTO: el levantamiento se modificó en otro equipo (versión % en el servidor, % en este equipo).', l.version, p_version;
  end if;
  perform public.fn_lev_validar(p_contenido);
  update public.levantamientos
     set contenido = p_contenido, tipo = p_contenido ->> 'tipo', version = l.version + 1
   where id = p_id;
  return l.version + 1;
end $$;

-- Registrar (o actualizar la descripción de) una foto ya subida al depósito
drop function if exists public.rpc_foto_registrar(jsonb);
create function public.rpc_foto_registrar(p jsonb) returns void
language plpgsql security definer set search_path = public, storage as $$
declare v_lev uuid := (p ->> 'levantamiento_id')::uuid; v_id uuid := (p ->> 'id')::uuid; v_ruta text;
begin
  if not public.fn_puede_editar_levantamiento(v_lev) then
    raise exception 'No puede agregar fotos a este levantamiento.';
  end if;
  v_ruta := v_lev || '/' || v_id || '.jpg';
  if not exists (select 1 from storage.objects where bucket_id = 'levantamientos' and name = v_ruta) then
    raise exception 'La foto no está en el depósito: súbala antes de registrarla.';
  end if;
  insert into public.levantamiento_fotos (id, levantamiento_id, ruta, seccion, referencia, descripcion,
                                          tomada_en, latitud, longitud, bytes, ancho, alto, creado_por)
  values (v_id, v_lev, v_ruta, p ->> 'seccion', nullif(p ->> 'referencia', ''), nullif(trim(p ->> 'descripcion'), ''),
          coalesce((p ->> 'tomada_en')::timestamptz, now()), (p ->> 'latitud')::numeric, (p ->> 'longitud')::numeric,
          (p ->> 'bytes')::integer, (p ->> 'ancho')::smallint, (p ->> 'alto')::smallint, public.fn_mi_perfil_id())
  on conflict (id) do update set descripcion = excluded.descripcion, referencia = excluded.referencia,
                                 seccion = excluded.seccion
  where levantamiento_fotos.levantamiento_id = v_lev;
exception
  when check_violation or not_null_violation or invalid_text_representation then
    raise exception 'Revise los datos de la foto (%).', sqlerrm;
end $$;

-- Quitar la ficha de una foto. Devuelve la ruta para que la aplicación borre el archivo.
drop function if exists public.rpc_foto_eliminar(uuid);
create function public.rpc_foto_eliminar(p_id uuid) returns text
language plpgsql security definer set search_path = public as $$
declare f public.levantamiento_fotos;
begin
  select * into f from public.levantamiento_fotos where id = p_id;
  if not found then return null; end if;
  if not public.fn_puede_editar_levantamiento(f.levantamiento_id) then
    raise exception 'No puede quitar fotos de este levantamiento.';
  end if;
  delete from public.levantamiento_fotos where id = p_id;
  return f.ruta;
end $$;

-- Enviar a revisión
drop function if exists public.rpc_levantamiento_enviar(uuid);
create function public.rpc_levantamiento_enviar(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare l public.levantamientos; v_yo uuid := public.fn_mi_perfil_id();
begin
  select * into l from public.levantamientos where id = p_id and es_prueba = public.fn_modo_prueba() for update;
  if not found then raise exception 'El levantamiento indicado no existe.'; end if;
  if not public.fn_puede_editar_levantamiento(p_id) then
    raise exception 'Solo el responsable o la coordinación envían a revisión un levantamiento en borrador o devuelto.';
  end if;
  if coalesce(l.contenido -> 'visita' ->> 'fecha', '') = '' then
    raise exception 'Falta la fecha de la visita (paso 1).';
  end if;
  if coalesce(jsonb_array_length(l.contenido -> 'areas'), 0) = 0 then
    raise exception 'Registre al menos un área (paso 3).';
  end if;
  update public.levantamientos set estado = 'en_revision', enviado_en = now(), observaciones_revision = null where id = p_id;
  insert into public.levantamiento_estados (levantamiento_id, estado_antes, estado_nuevo, perfil_id)
  values (p_id, l.estado, 'en_revision', v_yo);
  perform public.fn_avisar(array(select x from unnest(public.fn_perfiles_conduccion()) x where x is distinct from v_yo),
    'levantamiento_revision', l.codigo || ' para revisión', 'Informe de levantamiento enviado a revisión',
    '#/levantamientos/' || p_id);
end $$;

-- Revisión de la coordinación: aprobar o devolver con observaciones
drop function if exists public.rpc_levantamiento_revisar(uuid, boolean, text);
create function public.rpc_levantamiento_revisar(p_id uuid, p_aprobar boolean, p_observaciones text)
returns void language plpgsql security definer set search_path = public as $$
declare l public.levantamientos; v_yo uuid := public.fn_mi_perfil_id(); v_nuevo text;
begin
  if not public.fn_conduce() then raise exception 'Solo la coordinación o la gerencia revisan levantamientos.'; end if;
  select * into l from public.levantamientos where id = p_id and es_prueba = public.fn_modo_prueba() for update;
  if not found then raise exception 'El levantamiento indicado no existe.'; end if;
  if l.estado <> 'en_revision' then
    raise exception 'El levantamiento no está en revisión (estado: %).', public.fn_nombre_estado_lev(l.estado);
  end if;
  if p_aprobar is null then raise exception 'Indique si aprueba o devuelve.'; end if;
  if not p_aprobar and length(trim(coalesce(p_observaciones, ''))) < 3 then
    raise exception 'Indique las observaciones para devolver el levantamiento.';
  end if;
  v_nuevo := case when p_aprobar then 'aprobado' else 'devuelto' end;
  update public.levantamientos
     set estado = v_nuevo, observaciones_revision = nullif(trim(p_observaciones), ''),
         aprobado_por = case when p_aprobar then v_yo end, aprobado_en = case when p_aprobar then now() end
   where id = p_id;
  insert into public.levantamiento_estados (levantamiento_id, estado_antes, estado_nuevo, motivo, perfil_id)
  values (p_id, 'en_revision', v_nuevo, nullif(trim(p_observaciones), ''), v_yo);
  perform public.fn_avisar(array(select x from unnest(array[l.responsable_id]) x where x is distinct from v_yo),
    'levantamiento_revisado', l.codigo || ': ' || lower(public.fn_nombre_estado_lev(v_nuevo)),
    coalesce(nullif(trim(p_observaciones), ''), 'Informe aprobado'), '#/levantamientos/' || p_id);
end $$;

-- -----------------------------------------------------------------------------
-- 4. Disparadores (sin auditoría del contenido: se guarda cada pocos segundos y el
--    historial de estados ya registra quién envió, devolvió o aprobó)
-- -----------------------------------------------------------------------------
drop trigger if exists trg_levantamientos_actualizado on public.levantamientos;
create trigger trg_levantamientos_actualizado before update on public.levantamientos
for each row execute function public.trg_actualizado_en();

-- -----------------------------------------------------------------------------
-- 5. Depósito de fotos (privado; solo JPEG de hasta 5 MB; la aplicación las reduce a ~300 KB)
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('levantamientos', 'levantamientos', false, 5242880, array['image/jpeg'])
on conflict (id) do update set public = false, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg'];

create policy sgp_lev_fotos_ver on storage.objects for select to authenticated
  using (bucket_id = 'levantamientos' and public.fn_puede_ver_levantamiento(public.fn_lev_desde_ruta(name)));
create policy sgp_lev_fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'levantamientos' and name ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}\.jpg$'
              and public.fn_puede_editar_levantamiento(public.fn_lev_desde_ruta(name)));
create policy sgp_lev_fotos_cambiar on storage.objects for update to authenticated
  using (bucket_id = 'levantamientos' and public.fn_puede_editar_levantamiento(public.fn_lev_desde_ruta(name)))
  with check (bucket_id = 'levantamientos' and public.fn_puede_editar_levantamiento(public.fn_lev_desde_ruta(name)));
create policy sgp_lev_fotos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'levantamientos' and public.fn_puede_editar_levantamiento(public.fn_lev_desde_ruta(name)));

-- -----------------------------------------------------------------------------
-- 6. Seguridad a nivel de fila
-- -----------------------------------------------------------------------------
alter table public.levantamientos enable row level security;
alter table public.levantamiento_fotos enable row level security;
alter table public.levantamiento_estados enable row level security;

revoke all on public.levantamientos, public.levantamiento_fotos, public.levantamiento_estados from anon, authenticated;
grant select on public.levantamientos, public.levantamiento_fotos, public.levantamiento_estados to authenticated;

create policy p_levantamientos_ver on public.levantamientos for select to authenticated
  using (public.fn_puede_ver_requerimiento(requerimiento_id));
create policy p_modo_levantamientos on public.levantamientos as restrictive for select to authenticated
  using (es_prueba = public.fn_modo_prueba());
create policy p_lev_fotos_ver on public.levantamiento_fotos for select to authenticated
  using (public.fn_puede_ver_levantamiento(levantamiento_id));
create policy p_lev_estados_ver on public.levantamiento_estados for select to authenticated
  using (public.fn_puede_ver_levantamiento(levantamiento_id));

revoke all on function public.fn_lev_contenido_inicial(uuid, text) from public, anon, authenticated;
revoke all on function public.fn_lev_validar(jsonb)                from public, anon, authenticated;
do $$
declare f text;
begin
  foreach f in array array[
    -- las usan las políticas (se evalúan con el rol de quien consulta)
    'public.fn_puede_ver_levantamiento(uuid)', 'public.fn_puede_editar_levantamiento(uuid)',
    'public.fn_lev_desde_ruta(text)', 'public.fn_nombre_estado_lev(text)',
    'public.rpc_levantamiento_crear(uuid, uuid, jsonb)', 'public.rpc_levantamiento_guardar(uuid, jsonb, integer)',
    'public.rpc_foto_registrar(jsonb)', 'public.rpc_foto_eliminar(uuid)',
    'public.rpc_levantamiento_enviar(uuid)', 'public.rpc_levantamiento_revisar(uuid, boolean, text)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

update public.sistema_config set version_esquema = '0.3', actualizado_en = now() where id and version_esquema < '0.3';

-- -----------------------------------------------------------------------------
-- Comprobaciones
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
  if (select count(*) from pg_policies where schemaname = 'public' and tablename in ('perfiles', 'requerimientos')) < 3 then
    raise exception 'Faltan políticas del 00 o del 01: ejecute primero esos archivos.';
  end if;
  if (select count(*) from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname like 'sgp_lev_%') <> 4 then
    raise exception 'Faltan las políticas del depósito de fotos.';
  end if;
  if not exists (select 1 from storage.buckets where id = 'levantamientos' and not public) then
    raise exception 'El depósito de fotos no existe o es público.';
  end if;
  raise notice 'OK · versión de esquema 0.3: levantamientos';
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
select 'depósito de fotos', (select case when public then 'PÚBLICO (revisar)' else 'privado' end
                             || ' · ' || coalesce(file_size_limit / 1048576, 0) || ' MB máx.'
                             from storage.buckets where id = 'levantamientos')
          || ' · ' || (select count(*) from pg_policies where schemaname = 'storage' and policyname like 'sgp_lev_%') || ' políticas'
union all
select 'levantamientos · fotos', (select count(*) from public.levantamientos) || ' · ' || (select count(*) from public.levantamiento_fotos);
