-- =============================================================================
-- Prueba de sql/02_levantamientos.sql
-- =============================================================================
set client_min_messages = notice;

-- Preparación: coordinación, dos ingenieros, dos vendedores, un requerimiento asignado a Luis
select set_config('t.coord', public.banco_crear_cuenta('coord@refri.test', 'Carla Coordinadora')::text, false);
update public.perfiles set rol = 'coordinador' where correo = 'coord@refri.test';
select set_config('t.admin', public.banco_crear_cuenta('admin@refri.test', 'Andrés Admin')::text, false);
update public.perfiles set rol = 'admin' where correo = 'admin@refri.test';
select set_config('t.rosa',  public.banco_crear_cuenta('rosa@refri.test', 'Rosa Ventas')::text, false);
update public.perfiles set rol = 'ventas' where correo = 'rosa@refri.test';
select set_config('t.pedro', public.banco_crear_cuenta('pedro@refri.test', 'Pedro Ventas')::text, false);
update public.perfiles set rol = 'ventas' where correo = 'pedro@refri.test';
select set_config('t.luis',  public.banco_crear_cuenta('luis@refri.test', 'Luis Ingeniero')::text, false);
update public.perfiles set rol = 'ingeniero' where correo = 'luis@refri.test';
select set_config('t.eva',   public.banco_crear_cuenta('eva@refri.test', 'Eva Ingeniera')::text, false);
update public.perfiles set rol = 'ingeniero' where correo = 'eva@refri.test';
select set_config('t.aa', to_char(extract(year from now() at time zone 'America/Caracas')::int % 100, 'FM00'), false);

create or replace function pg_temp.pid(p_auth text) returns uuid language sql as
  $$ select id from public.perfiles where auth_id = current_setting(p_auth)::uuid $$;
-- Un archivo en el depósito, como lo deja la subida desde la aplicación
create or replace function pg_temp.subir(p_lev uuid, p_foto uuid) returns void language sql as
  $$ insert into storage.objects (bucket_id, name, owner) values ('levantamientos', p_lev || '/' || p_foto || '.jpg', auth.uid()) $$;
grant execute on function pg_temp.pid(text), pg_temp.subir(uuid, uuid) to authenticated;

select public.banco_como(current_setting('t.rosa')::uuid);
select set_config('t.cli', (public.rpc_cliente_guardar(null, '{"razon_social":"Clínica Santa Ana C.A.","rif":"J-30111222-3"}') ->> 'id'), false);
select set_config('t.req', (public.rpc_requerimiento_registrar(jsonb_build_object(
  'cliente_id', current_setting('t.cli'), 'obra_nombre', 'Quirófanos', 'direccion', 'Calle 3', 'estado_geo', 'Miranda',
  'ciudad', 'Los Teques', 'tipo_edificacion', 'salud', 'tipo_solicitud', 'sistema_nuevo',
  'sistemas', jsonb_build_array('uma', 'presurizacion'), 'descripcion', 'Adecuación de 3 quirófanos',
  'contacto_nombre', 'Dr. Ruiz', 'contacto_telefono', '0412-0000000')) ->> 'id'), false);
select set_config('t.req_sin', (public.rpc_requerimiento_registrar(jsonb_build_object(
  'cliente_id', current_setting('t.cli'), 'obra_nombre', 'Depósito', 'direccion', 'Zona industrial', 'estado_geo', 'Miranda',
  'ciudad', 'Guarenas', 'tipo_solicitud', 'diagnostico', 'descripcion', 'Diagnóstico de extracción')) ->> 'id'), false);
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
select public.rpc_requerimiento_asignar(current_setting('t.req')::uuid, 'B', pg_temp.pid('t.luis'), array['HV'], null, null);
reset role;

-- 1. Iniciar ------------------------------------------------------------------------
select public.banco_como(current_setting('t.eva')::uuid);
do $$ begin
  begin
    perform public.rpc_levantamiento_crear(gen_random_uuid(), current_setting('t.req')::uuid, null);
    raise exception '1a · Un ingeniero no asignado inició el levantamiento.';
  exception when raise_exception then if sqlerrm like '1a%' then raise; end if; end;
end $$;
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
do $$ begin
  begin
    perform public.rpc_levantamiento_crear(gen_random_uuid(), current_setting('t.req_sin')::uuid, null);
    raise exception '1b · Se inició un levantamiento de un requerimiento sin asignar.';
  exception when raise_exception then if sqlerrm like '1b%' then raise; end if; end;
end $$;
reset role;
select public.banco_como(current_setting('t.luis')::uuid);
do $$
declare v jsonb; c jsonb;
begin
  -- Iniciado sin señal: el teléfono generó el id; al reintentar no se duplica
  v := public.rpc_levantamiento_crear('0e6f2b9a-1111-4c1d-9a2b-000000000001', current_setting('t.req')::uuid, null);
  perform set_config('t.lev', v ->> 'id', false);
  if (public.rpc_levantamiento_crear('0e6f2b9a-1111-4c1d-9a2b-000000000001', current_setting('t.req')::uuid, null) ->> 'codigo')
     <> v ->> 'codigo' or (select count(*) from public.levantamientos) <> 1 then
    raise exception '1g · El reintento sin señal creó otro levantamiento o cambió el código.';
  end if;
  if v ->> 'codigo' <> 'PRB-' || current_setting('t.aa') || '-0001-GE-IL-001' then
    raise exception '1c · Código inesperado: %', v ->> 'codigo';
  end if;
  select contenido into c from public.levantamientos where id = (v ->> 'id')::uuid;
  if c ->> 'tipo' <> 'nueva' or c -> 'visita' ->> 'cliente' <> 'Clínica Santa Ana C.A.' or c -> 'visita' ->> 'rif' <> 'J-30111222-3'
     or c ->> 'alcance' <> 'Adecuación de 3 quirófanos' or c -> 'visita' ->> 'sistemas' <> 'UMA, Presurización'
     or c -> 'visita' ->> 'tipo_instalacion' <> 'Salud' then
    raise exception '1d · El contenido no se llenó desde el requerimiento: %', c;
  end if;
  if (select estado from public.requerimientos where id = current_setting('t.req')::uuid) <> 'en_levantamiento' then
    raise exception '1e · El requerimiento no pasó a En levantamiento.';
  end if;
  -- Con el contenido que el teléfono ya había llenado sin señal
  v := public.rpc_levantamiento_crear(gen_random_uuid(), current_setting('t.req')::uuid,
         '{"tipo":"existente","visita":{"fecha":"2026-10-24"},"areas":[]}');
  perform set_config('t.lev2', v ->> 'id', false);
  if (select contenido -> 'visita' ->> 'fecha' from public.levantamientos where id = (v ->> 'id')::uuid) <> '2026-10-24'
     or (select tipo from public.levantamientos where id = (v ->> 'id')::uuid) <> 'existente' then
    raise exception '1h · No se conservó el contenido llenado sin señal.';
  end if;
  if v ->> 'codigo' not like '%-GE-IL-002' then raise exception '1f · El segundo levantamiento no es IL-002: %', v ->> 'codigo'; end if;
  raise notice '1 · iniciar (también sin señal): solo el asignado o la coordinación; sin duplicar al reintentar; código %', v ->> 'codigo';
end $$;
reset role;

-- 2. Guardar con control de versión --------------------------------------------------
select public.banco_como(current_setting('t.luis')::uuid);
do $$
declare v int; c jsonb;
begin
  select contenido into c from public.levantamientos where id = current_setting('t.lev')::uuid;
  c := jsonb_set(c, '{visita,fecha}', '"2026-10-23"');
  v := public.rpc_levantamiento_guardar(current_setting('t.lev')::uuid, c, 1);
  if v <> 2 then raise exception '2a · La versión no subió a 2: %', v; end if;
  begin
    perform public.rpc_levantamiento_guardar(current_setting('t.lev')::uuid, c, 1);
    raise exception '2b · Se aceptó una copia vieja (versión 1).';
  exception when raise_exception then
    if sqlerrm not like 'CONFLICTO:%' then raise exception '2b · Se aceptó una copia vieja (%).', sqlerrm; end if;
  end;
  v := public.rpc_levantamiento_guardar(current_setting('t.lev')::uuid, c, null);  -- la persona eligió su copia
  if v <> 3 then raise exception '2c · Sobrescribir no funcionó.'; end if;
  begin
    perform public.rpc_levantamiento_guardar(current_setting('t.lev')::uuid, jsonb_set(c, '{tipo}', '"otro"'), 3);
    raise exception '2d · Se aceptó un tipo inválido.';
  exception when raise_exception then if sqlerrm like '2d%' then raise; end if; end;
  begin
    perform public.rpc_levantamiento_guardar(current_setting('t.lev')::uuid, jsonb_set(c, '{areas}', '"texto"'), 3);
    raise exception '2e · Se aceptó una lista de áreas mal formada.';
  exception when raise_exception then if sqlerrm like '2e%' then raise; end if; end;
  c := jsonb_set(jsonb_set(c, '{tipo}', '"mixto"'), '{areas}',
                 '[{"id":"a1","nombre":"Quirófano 1","largo":6,"ancho":5,"alto":3,"paredes_sol":2,"techos_sol":1}]');
  v := public.rpc_levantamiento_guardar(current_setting('t.lev')::uuid, c, 3);
  if (select tipo from public.levantamientos where id = current_setting('t.lev')::uuid) <> 'mixto' then
    raise exception '2f · El cambio de tipo no se guardó en la columna.';
  end if;
end $$;
reset role;
select public.banco_como(current_setting('t.eva')::uuid);
do $$ begin
  begin
    perform public.rpc_levantamiento_guardar(current_setting('t.lev')::uuid, '{"tipo":"nueva"}', null);
    raise exception '2g · Otro ingeniero modificó el levantamiento.';
  exception when raise_exception then if sqlerrm like '2g%' then raise; end if; end;
  raise notice '2 · guardar: versión, conflicto detectado, tipo y listas validados, solo el responsable';
end $$;
reset role;

-- 3. Quién lo ve ------------------------------------------------------------------------
select public.banco_como(current_setting('t.rosa')::uuid);
do $$ begin
  if (select count(*) from public.levantamientos) <> 2 then raise exception '3a · El vendedor del requerimiento no ve sus levantamientos.'; end if;
end $$;
reset role;
select public.banco_como(current_setting('t.pedro')::uuid);
do $$ begin
  if (select count(*) from public.levantamientos) <> 0 then raise exception '3b · Otro vendedor ve levantamientos ajenos.'; end if;
end $$;
reset role;
select public.banco_como(current_setting('t.eva')::uuid);
do $$ begin
  if (select count(*) from public.levantamientos) <> 0 then raise exception '3c · Otro ingeniero ve levantamientos ajenos.'; end if;
  if (select count(*) from public.levantamiento_estados) <> 0 then raise exception '3d · Otro ingeniero ve el historial ajeno.'; end if;
  raise notice '3 · lectura: responsable, vendedor del requerimiento y conducción; nadie más';
end $$;
reset role;

-- 4. Fotos en el depósito ---------------------------------------------------------------
select public.banco_como(current_setting('t.luis')::uuid);
select set_config('t.foto', gen_random_uuid()::text, false);
do $$ begin
  begin
    perform public.rpc_foto_registrar(jsonb_build_object('id', current_setting('t.foto'), 'levantamiento_id', current_setting('t.lev'),
      'seccion', 'area', 'referencia', 'a1', 'tomada_en', now()));
    raise exception '4a · Se registró una foto que no está en el depósito.';
  exception when raise_exception then if sqlerrm like '4a%' then raise; end if; end;
  perform pg_temp.subir(current_setting('t.lev')::uuid, current_setting('t.foto')::uuid);
  perform public.rpc_foto_registrar(jsonb_build_object('id', current_setting('t.foto'), 'levantamiento_id', current_setting('t.lev'),
    'seccion', 'area', 'referencia', 'a1', 'descripcion', 'Fachada norte', 'tomada_en', now(),
    'latitud', 10.343, 'longitud', -67.043, 'bytes', 284000, 'ancho', 1600, 'alto', 1200));
  -- Registrar de nuevo (reintento sin señal) no duplica; actualiza la descripción
  perform public.rpc_foto_registrar(jsonb_build_object('id', current_setting('t.foto'), 'levantamiento_id', current_setting('t.lev'),
    'seccion', 'area', 'referencia', 'a1', 'descripcion', 'Fachada norte, ventanales', 'tomada_en', now()));
  if (select count(*) from public.levantamiento_fotos) <> 1
     or (select descripcion from public.levantamiento_fotos) <> 'Fachada norte, ventanales' then
    raise exception '4b · El reintento duplicó la foto o no actualizó la descripción.';
  end if;
  begin
    insert into storage.objects (bucket_id, name) values ('levantamientos', 'cualquier/cosa.png');
    raise exception '4c · Se aceptó un archivo con ruta inválida.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select public.banco_como(current_setting('t.eva')::uuid);
do $$ begin
  begin
    perform pg_temp.subir(current_setting('t.lev')::uuid, gen_random_uuid());
    raise exception '4d · Otro ingeniero subió una foto al levantamiento.';
  exception when insufficient_privilege then null; end;
  if (select count(*) from storage.objects) <> 0 then raise exception '4e · Otro ingeniero ve las fotos.'; end if;
end $$;
reset role;
select public.banco_como(current_setting('t.rosa')::uuid);
do $$ begin
  if (select count(*) from storage.objects) <> 1 then raise exception '4f · El vendedor no ve la foto de su requerimiento.'; end if;
  if (select count(*) from public.levantamiento_fotos) <> 1 then raise exception '4g · El vendedor no ve la ficha de la foto.'; end if;
  raise notice '4 · fotos: solo con archivo subido, sin duplicados, ruta validada, visibles para quien ve el levantamiento';
end $$;
reset role;

-- 5. Enviar a revisión -----------------------------------------------------------------
select public.banco_como(current_setting('t.luis')::uuid);
do $$ begin
  begin
    perform public.rpc_levantamiento_enviar(current_setting('t.lev2')::uuid);
    raise exception '5a · Se envió sin áreas.';
  exception when raise_exception then if sqlerrm like '5a%' then raise; end if; end;
  perform public.rpc_levantamiento_enviar(current_setting('t.lev')::uuid);
  if (select estado from public.levantamientos where id = current_setting('t.lev')::uuid) <> 'en_revision' then
    raise exception '5b · No pasó a En revisión.';
  end if;
  begin
    perform public.rpc_levantamiento_guardar(current_setting('t.lev')::uuid, '{"tipo":"nueva"}', null);
    raise exception '5c · Se modificó un levantamiento en revisión.';
  exception when raise_exception then if sqlerrm like '5c%' then raise; end if; end;
  begin
    perform pg_temp.subir(current_setting('t.lev')::uuid, gen_random_uuid());
    raise exception '5d · Se subió una foto a un levantamiento en revisión.';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
do $$ begin
  if (select count(*) from public.notificaciones where tipo = 'levantamiento_revision') <> 1 then
    raise exception '5e · La coordinación no recibió el aviso de revisión.';
  end if;
  raise notice '5 · enviar: exige fecha y áreas; bloquea contenido y fotos; avisa a la coordinación';
end $$;
reset role;

-- 6. Revisión ---------------------------------------------------------------------------
select public.banco_como(current_setting('t.luis')::uuid);
do $$ begin
  begin
    perform public.rpc_levantamiento_revisar(current_setting('t.lev')::uuid, true, null);
    raise exception '6a · El ingeniero aprobó su propio levantamiento.';
  exception when raise_exception then if sqlerrm like '6a%' then raise; end if; end;
end $$;
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
do $$ begin
  begin
    perform public.rpc_levantamiento_revisar(current_setting('t.lev')::uuid, false, '');
    raise exception '6b · Se devolvió sin observaciones.';
  exception when raise_exception then if sqlerrm like '6b%' then raise; end if; end;
  perform public.rpc_levantamiento_revisar(current_setting('t.lev')::uuid, false, 'Falta la capacidad del tablero');
end $$;
reset role;
select public.banco_como(current_setting('t.luis')::uuid);
do $$
declare v int;
begin
  if (select count(*) from public.notificaciones where tipo = 'levantamiento_revisado') <> 1 then
    raise exception '6c · El responsable no recibió la devolución.';
  end if;
  v := public.rpc_levantamiento_guardar(current_setting('t.lev')::uuid,
         (select contenido from public.levantamientos where id = current_setting('t.lev')::uuid), null);
  perform public.rpc_levantamiento_enviar(current_setting('t.lev')::uuid);
end $$;
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
select public.rpc_levantamiento_revisar(current_setting('t.lev')::uuid, true, null);
reset role;
select public.banco_como(current_setting('t.luis')::uuid);
do $$ begin
  if (select estado from public.levantamientos where id = current_setting('t.lev')::uuid) <> 'aprobado'
     or (select aprobado_por from public.levantamientos where id = current_setting('t.lev')::uuid) <> pg_temp.pid('t.coord') then
    raise exception '6d · No quedó aprobado por la coordinación.';
  end if;
  begin
    perform public.rpc_foto_eliminar(current_setting('t.foto')::uuid);
    raise exception '6e · Se quitó una foto de un levantamiento aprobado.';
  exception when raise_exception then if sqlerrm like '6e%' then raise; end if; end;
  if (select count(*) from public.levantamiento_estados where levantamiento_id = current_setting('t.lev')::uuid) <> 5 then
    raise exception '6f · El historial no tiene los 5 movimientos: %',
      (select count(*) from public.levantamiento_estados where levantamiento_id = current_setting('t.lev')::uuid);
  end if;
  raise notice '6 · revisión: solo la coordinación; devolver exige observaciones; aprobado queda bloqueado';
end $$;
reset role;

-- 7. Operación real: lo de prácticas desaparece -----------------------------------------
select public.banco_como(current_setting('t.admin')::uuid);
select public.rpc_cambiar_modo('operacion', 'Inicio de operación real');
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
do $$ begin
  if (select count(*) from public.levantamientos) <> 0 then raise exception '7a · Los levantamientos de prácticas siguen visibles.'; end if;
  begin
    perform public.rpc_levantamiento_guardar(current_setting('t.lev2')::uuid, '{"tipo":"nueva"}', null);
    raise exception '7b · Se modificó un levantamiento de prácticas en operación real.';
  exception when raise_exception then if sqlerrm like '7b%' then raise; end if; end;
  raise notice '7 · operación real: levantamientos de prácticas ocultos y bloqueados';
end $$;
reset role;

-- 8. Sin sesión, nada --------------------------------------------------------------------
select public.banco_como_anonimo();
do $$ begin
  begin
    perform count(*) from public.levantamientos;
    raise exception '8a · anon puede leer levantamientos.';
  exception when insufficient_privilege then null; end;
  if (select count(*) from storage.objects) <> 0 then raise exception '8b · anon ve fotos.'; end if;
  raise notice '8 · visitante sin sesión: sin acceso';
end $$;
reset role;
