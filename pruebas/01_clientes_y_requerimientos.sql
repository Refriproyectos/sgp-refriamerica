-- =============================================================================
-- Prueba de sql/01_clientes_y_requerimientos.sql
-- =============================================================================
set client_min_messages = notice;

-- Preparación ---------------------------------------------------------------------
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
-- Un vendedor que existe en Personal pero no tiene cuenta de acceso
insert into public.perfiles (nombre, rol) values ('Vendedor Sin Cuenta', 'ventas');
select set_config('t.aa', to_char(extract(year from now() at time zone 'America/Caracas')::int % 100, 'FM00'), false);

create or replace function pg_temp.pid(p_auth text) returns uuid language sql as
  $$ select id from public.perfiles where auth_id = current_setting(p_auth)::uuid $$;
create or replace function pg_temp.ficha(p_cliente uuid, p_obra text, p_vendedor uuid default null) returns jsonb language sql as $$
  select jsonb_build_object('cliente_id', p_cliente, 'vendedor_id', p_vendedor, 'canal', 'visita',
    'obra_nombre', p_obra, 'direccion', 'Av. Principal', 'estado_geo', 'Aragua', 'ciudad', 'Maracay',
    'tipo_edificacion', 'comercial', 'area_m2', '250', 'niveles', '1', 'tipo_solicitud', 'sistema_nuevo',
    'sistemas', jsonb_build_array('expansion_directa', 'ventilacion_extraccion'),
    'descripcion', 'Climatización de salón y extracción de cocina',
    'info_recibida', jsonb_build_array('fotos'), 'requiere_levantamiento', true,
    'fecha_requerida', '2026-11-15', 'prioridad', 'alta')
$$;
grant execute on function pg_temp.pid(text), pg_temp.ficha(uuid, text, uuid) to authenticated;

-- 1. Clientes -------------------------------------------------------------------------
select public.banco_como(current_setting('t.rosa')::uuid);
do $$
declare v jsonb;
begin
  v := public.rpc_cliente_guardar(null, '{"razon_social":"Inversiones La Esquina C.A.","rif":"j-12345678-9","tipo":"privado"}');
  if v ->> 'codigo' !~ '^CLI-[0-9]{4}$' then raise exception '1a · Código de cliente inesperado: %', v ->> 'codigo'; end if;
  perform set_config('t.cli1', v ->> 'id', false);
  if (select rif from public.clientes where id = (v ->> 'id')::uuid) <> 'J-12345678-9' then
    raise exception '1b · El RIF no se normalizó a mayúsculas.';
  end if;
  begin
    perform public.rpc_cliente_guardar(null, '{"razon_social":"Mal RIF","rif":"12345"}');
    raise exception '1c · Se aceptó un RIF inválido.';
  exception when raise_exception then if sqlerrm like '1c%' then raise; end if; end;
  begin
    perform public.rpc_cliente_guardar(null, '{"razon_social":"Duplicado","rif":"J-12345678-9"}');
    raise exception '1d · Se aceptó un RIF duplicado.';
  exception when raise_exception then if sqlerrm like '1d%' then raise; end if; end;
  v := public.rpc_cliente_guardar(null, '{"razon_social":"Hotel Costa Azul"}');
  perform set_config('t.cli2', v ->> 'id', false);
  raise notice '1 · clientes: código, RIF validado y sin duplicados';
end $$;
reset role;
select public.banco_como(current_setting('t.luis')::uuid);
do $$
begin
  begin
    perform public.rpc_cliente_guardar(null, '{"razon_social":"Intruso"}');
    raise exception '1e · Un ingeniero registró un cliente.';
  exception when raise_exception then if sqlerrm like '1e%' then raise; end if; end;
  if (select count(*) from public.clientes) <> 2 then raise exception '1f · Un ingeniero no ve el catálogo de clientes.'; end if;
end $$;
reset role;

-- 2. Registro por Ventas: código del año en modo prueba, vendedor forzado a sí mismo ------
select public.banco_como(current_setting('t.rosa')::uuid);
do $$
declare v jsonb; w jsonb;
begin
  v := public.rpc_requerimiento_registrar(pg_temp.ficha(current_setting('t.cli1')::uuid, 'Rest. La Esquina', pg_temp.pid('t.pedro')));
  if v ->> 'codigo' <> 'PRB-' || current_setting('t.aa') || '-0001' then
    raise exception '2a · Código inesperado en modo prueba: %', v ->> 'codigo';
  end if;
  if (select vendedor_id from public.requerimientos where id = (v ->> 'id')::uuid) <> pg_temp.pid('t.rosa') then
    raise exception '2b · Ventas pudo registrar a nombre de otro vendedor.';
  end if;
  w := public.rpc_requerimiento_registrar(pg_temp.ficha(current_setting('t.cli2')::uuid, 'Hotel Costa Azul'));
  if w ->> 'codigo' <> 'PRB-' || current_setting('t.aa') || '-0002' then raise exception '2c · El correlativo no avanzó: %', w ->> 'codigo'; end if;
  perform set_config('t.req1', v ->> 'id', false);
  perform set_config('t.req2', w ->> 'id', false);
  begin
    perform public.rpc_requerimiento_registrar(pg_temp.ficha(current_setting('t.cli1')::uuid, 'Sin estado') - 'estado_geo');
    raise exception '2d · Se aceptó un requerimiento sin estado.';
  exception when raise_exception then if sqlerrm like '2d%' then raise; end if;
                                     if sqlerrm not like 'Revise los datos%' then raise exception '2e · Mensaje poco claro: %', sqlerrm; end if; end;
  raise notice '2 · registro por Ventas: código PRB-AA-NNNN y vendedor propio';
end $$;
reset role;

-- 3. Registro por la coordinación: elige vendedor, que debe ser de Ventas --------------
select public.banco_como(current_setting('t.coord')::uuid);
do $$
declare v jsonb;
begin
  begin
    perform public.rpc_requerimiento_registrar(pg_temp.ficha(current_setting('t.cli1')::uuid, 'X', pg_temp.pid('t.luis')));
    raise exception '3a · Se aceptó un vendedor que no es de Ventas.';
  exception when raise_exception then if sqlerrm like '3a%' then raise; end if; end;
  v := public.rpc_requerimiento_registrar(pg_temp.ficha(current_setting('t.cli2')::uuid, 'Anexo Hotel',
         (select id from public.perfiles where nombre = 'Vendedor Sin Cuenta')));
  perform set_config('t.req3', v ->> 'id', false);
  if (select count(*) from public.requerimientos) <> 3 then raise exception '3b · La coordinación no ve todos los requerimientos.'; end if;
  if (select count(*) from public.notificaciones where tipo = 'requerimiento_nuevo') < 3 then
    raise exception '3c · La coordinación no recibió los avisos de requerimientos nuevos.';
  end if;
  raise notice '3 · registro por la coordinación: vendedor sin cuenta permitido; avisos a la coordinación';
end $$;
reset role;

-- 4. Visibilidad por rol -------------------------------------------------------------
select public.banco_como(current_setting('t.luis')::uuid);
do $$ begin
  if (select count(*) from public.requerimientos) <> 0 then raise exception '4a · Un ingeniero ve requerimientos que no le asignaron.'; end if;
end $$;
reset role;
select public.banco_como(current_setting('t.pedro')::uuid);
do $$ begin
  if (select count(*) from public.requerimientos) <> 0 then raise exception '4b · Un vendedor ve requerimientos de otro vendedor.'; end if;
  begin
    perform public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'cerrado', 'x');
    raise exception '4c · Un vendedor ajeno pudo cambiar el estado.';
  exception when raise_exception then if sqlerrm like '4c%' then raise; end if; end;
  raise notice '4 · visibilidad: ingeniero y vendedor solo ven lo suyo';
end $$;
reset role;

-- 5. Asignación ----------------------------------------------------------------------
select public.banco_como(current_setting('t.luis')::uuid);
do $$ begin
  begin
    perform public.rpc_requerimiento_asignar(current_setting('t.req1')::uuid, 'B', pg_temp.pid('t.luis'), array['HV'], null, null);
    raise exception '5a · Un ingeniero se asignó un requerimiento.';
  exception when raise_exception then if sqlerrm like '5a%' then raise; end if; end;
end $$;
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
select public.rpc_requerimiento_asignar(current_setting('t.req1')::uuid, 'B', pg_temp.pid('t.luis'), array['HV'], '2026-11-10', 'Visitar primero');
select public.rpc_requerimiento_asignar(current_setting('t.req2')::uuid, 'A', pg_temp.pid('t.eva'), array['HV'], null, null);
reset role;
select public.banco_como(current_setting('t.luis')::uuid);
do $$ begin
  if (select estado from public.requerimientos where id = current_setting('t.req1')::uuid) <> 'asignado' then
    raise exception '5b · El requerimiento no pasó a Asignado.';
  end if;
  if (select count(*) from public.requerimientos) <> 1 then raise exception '5c · El ingeniero no ve exactamente lo asignado.'; end if;
  if (select count(*) from public.notificaciones where tipo = 'requerimiento_asignado') <> 1 then
    raise exception '5d · El ingeniero no recibió el aviso de asignación.';
  end if;
  if (select count(*) from public.requerimiento_estados where requerimiento_id = current_setting('t.req1')::uuid) <> 2 then
    raise exception '5e · El historial no registró registro y asignación.';
  end if;
  raise notice '5 · asignación: solo la coordinación; aviso al ingeniero; historial';
end $$;

-- 6. Transiciones y quién puede hacerlas ---------------------------------------------
-- El salto inválido lo intenta la coordinación, que tiene todos los permisos: así solo
-- la regla de transiciones puede detenerlo (con el ingeniero lo frenaba la regla de rol).
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
do $$ begin
  begin
    perform public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'aprobado', null);
    raise exception '6a · Se saltó de Asignado a Aprobado.';
  exception when raise_exception then
    if sqlerrm not like 'No se puede pasar%' then raise exception '6a · Se saltó de Asignado a Aprobado (%).', sqlerrm; end if;
  end;
end $$;
reset role;
select public.banco_como(current_setting('t.luis')::uuid);
do $$ begin
  perform public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'en_levantamiento', null);
  perform public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'en_ingenieria', null);
  perform public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'enviado_ventas', null);
  begin
    perform public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'aprobado', null);
    raise exception '6b · El ingeniero registró la decisión del cliente.';
  exception when raise_exception then if sqlerrm like '6b%' then raise; end if; end;
end $$;
reset role;
select public.banco_como(current_setting('t.rosa')::uuid);
do $$ begin
  begin
    perform public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'rechazado', '');
    raise exception '6c · Se rechazó sin motivo.';
  exception when raise_exception then if sqlerrm like '6c%' then raise; end if; end;
  perform public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'en_espera', 'Cliente revisa presupuesto');
  perform public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'aprobado', null);
  begin
    perform public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'cerrado', null);
    raise exception '6d · Ventas cerró el requerimiento.';
  exception when raise_exception then if sqlerrm like '6d%' then raise; end if; end;
end $$;
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
select public.rpc_requerimiento_estado(current_setting('t.req1')::uuid, 'cerrado', 'Pasa a ingeniería de detalle');
do $$ begin
  if (select count(*) from public.requerimiento_estados where requerimiento_id = current_setting('t.req1')::uuid) <> 8 then
    raise exception '6e · El historial no tiene los 8 cambios: %',
      (select count(*) from public.requerimiento_estados where requerimiento_id = current_setting('t.req1')::uuid);
  end if;
  raise notice '6 · transiciones: válidas, por rol, con motivo cuando corresponde';
end $$;
reset role;

-- 7. Modalidad A: el ingeniero cierra al entregar la nota técnica ---------------------
select public.banco_como(current_setting('t.eva')::uuid);
select public.rpc_requerimiento_estado(current_setting('t.req2')::uuid, 'en_ingenieria', null);
select public.rpc_requerimiento_estado(current_setting('t.req2')::uuid, 'cerrado', 'Nota técnica entregada');
do $$ begin
  if (select estado from public.requerimientos where id = current_setting('t.req2')::uuid) <> 'cerrado' then
    raise exception '7a · La modalidad A no se pudo cerrar desde ingeniería.';
  end if;
  raise notice '7 · modalidad A: cierre directo al entregar la nota técnica';
end $$;
reset role;

-- 8. Paso a operación real: lo de prácticas desaparece y la numeración real empieza en 0001
select public.banco_como(current_setting('t.admin')::uuid);
select public.rpc_cambiar_modo('operacion', 'Inicio de operación real');
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
do $$
declare v jsonb;
begin
  if (select count(*) from public.requerimientos) <> 0 then raise exception '8a · Los requerimientos de prácticas siguen visibles.'; end if;
  v := public.rpc_requerimiento_registrar(pg_temp.ficha(current_setting('t.cli1')::uuid, 'Primera obra real', pg_temp.pid('t.rosa')));
  if v ->> 'codigo' <> 'PRY-' || current_setting('t.aa') || '-0001' then
    raise exception '8b · El primer requerimiento real no es PRY-%-0001: %', current_setting('t.aa'), v ->> 'codigo';
  end if;
  begin
    perform public.rpc_requerimiento_estado(current_setting('t.req3')::uuid, 'cerrado', 'x');
    raise exception '8c · Se pudo modificar un requerimiento de prácticas en operación real.';
  exception when raise_exception then if sqlerrm like '8c%' then raise; end if; end;
  raise notice '8 · operación real: prácticas ocultas; primer código PRY-%-0001', current_setting('t.aa');
end $$;
reset role;

-- 9. Sin sesión, nada ----------------------------------------------------------------
select public.banco_como_anonimo();
do $$ begin
  begin
    perform count(*) from public.requerimientos;
    raise exception '9a · anon puede leer requerimientos.';
  exception when insufficient_privilege then null; end;
  raise notice '9 · visitante sin sesión: sin acceso';
end $$;
reset role;
