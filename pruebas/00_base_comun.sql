-- =============================================================================
-- Prueba de sql/00_base_comun.sql
-- Corre dentro de una transacción que banco/probar.sh deshace al final.
-- Cada comprobación que falla lanza una excepción que nombra lo que falta.
-- =============================================================================
set client_min_messages = notice;

-- Preparación (como dueño de la base) ------------------------------------------
-- Una ficha creada por la coordinación ANTES de que exista la cuenta
insert into public.perfiles (nombre, correo, rol, disciplina)
values ('Luis Ingeniero', 'luis@refri.test', 'ingeniero', 'HV');

select set_config('t.coord', public.banco_crear_cuenta('coord@refri.test', 'Carla Coordinadora')::text, false);
update public.perfiles set rol = 'coordinador' where correo = 'coord@refri.test';
select set_config('t.admin', public.banco_crear_cuenta('admin@refri.test', 'Andrés Admin')::text, false);
update public.perfiles set rol = 'admin' where correo = 'admin@refri.test';
select set_config('t.luis',  public.banco_crear_cuenta('luis@refri.test')::text, false);
select set_config('t.ana',   public.banco_crear_cuenta('ana@refri.test', 'Ana Nueva')::text, false);

-- 1. Alta automática y enlace sin duplicar -------------------------------------
do $$
begin
  if (select count(*) from public.perfiles where lower(correo) = 'luis@refri.test') <> 1 then
    raise exception '1a · La cuenta de Luis duplicó su ficha en lugar de enlazarla.';
  end if;
  if (select rol from public.perfiles where auth_id = current_setting('t.luis')::uuid) <> 'ingeniero' then
    raise exception '1b · La ficha enlazada de Luis perdió su rol.';
  end if;
  if (select rol from public.perfiles where auth_id = current_setting('t.ana')::uuid) is not null then
    raise exception '1c · Una cuenta nueva no debe recibir rol automáticamente.';
  end if;
  if (select nombre from public.perfiles where auth_id = current_setting('t.ana')::uuid) <> 'Ana Nueva' then
    raise exception '1d · La ficha automática no tomó el nombre de la cuenta.';
  end if;
  raise notice '1 · alta automática y enlace sin duplicar: correcto';
end $$;

-- 2. Una cuenta sin rol solo se ve a sí misma ----------------------------------
select public.banco_como(current_setting('t.ana')::uuid);
do $$
begin
  if (select count(*) from public.perfiles) <> 1 then
    raise exception '2a · Una cuenta sin rol ve el directorio de personal.';
  end if;
  if (public.rpc_mi_sesion() ->> 'nombre') <> 'Ana Nueva' then
    raise exception '2b · rpc_mi_sesion no devuelve la ficha propia.';
  end if;
  raise notice '2 · cuenta sin rol: solo su propia ficha';
end $$;
reset role;

-- 3. Un ingeniero no administra personal ni escribe directo --------------------
select public.banco_como(current_setting('t.luis')::uuid);
do $$
begin
  if (select count(*) from public.perfiles) < 4 then
    raise exception '3a · Un ingeniero no ve el directorio completo.';
  end if;
  begin
    perform public.rpc_personal_guardar(null, 'Intruso', null, 'admin', null, null, null, null);
    raise exception '3b · Un ingeniero pudo registrar personal.';
  exception when raise_exception then
    if sqlerrm like '3b%' then raise; end if;
  end;
  begin
    insert into public.perfiles (nombre) values ('Directo');
    raise exception '3c · Un ingeniero escribió directamente en perfiles.';
  exception when insufficient_privilege then null;
  end;
  begin
    update public.perfiles set rol = 'admin' where auth_id = auth.uid();
    raise exception '3d · Un ingeniero se cambió el rol directamente.';
  exception when insufficient_privilege then null;
  end;
  raise notice '3 · ingeniero: ve el directorio, no administra ni escribe directo';
end $$;
reset role;

-- 4. El coordinador administra personal, pero no otorga administrador ----------
select public.banco_como(current_setting('t.coord')::uuid);
do $$
declare v uuid;
begin
  v := public.rpc_personal_guardar(null, 'Pedro Proyectista', 'Ingeniero de Proyectos', 'ingeniero',
                                   'pedro@refri.test', null, 'AU', '123456');
  if v is null then raise exception '4a · El coordinador no pudo registrar personal.'; end if;
  begin
    perform public.rpc_personal_guardar(v, 'Pedro Proyectista', null, 'admin', null, null, null, null);
    raise exception '4b · El coordinador otorgó el rol de administrador.';
  exception when raise_exception then
    if sqlerrm like '4b%' then raise; end if;
  end;
  begin
    perform public.rpc_personal_guardar(v, 'Pedro', null, 'ingeniero', null, null, 'XX', null);
    raise exception '4c · Se aceptó una disciplina inválida.';
  exception when raise_exception then
    if sqlerrm like '4c%' then raise; end if;
  end;
  begin
    perform public.rpc_personal_retirar(public.fn_mi_perfil_id(), 'prueba');
    raise exception '4d · El coordinador pudo retirar su propia ficha.';
  exception when raise_exception then
    if sqlerrm like '4d%' then raise; end if;
  end;
  perform public.rpc_personal_retirar(v, 'Prueba de retiro');
  if (select activo from public.perfiles where id = v) then
    raise exception '4e · El retiro no desactivó la ficha.';
  end if;
  raise notice '4 · coordinador: registra y retira; no otorga admin ni se retira a sí mismo';
end $$;
reset role;

-- 5. Vincular cuenta reemplaza la ficha automática vacía -----------------------
insert into public.perfiles (nombre, rol) values ('Rosa Ventas', 'ventas');
select set_config('t.rosa', public.banco_crear_cuenta('rosa.v@refri.test')::text, false);
select public.banco_como(current_setting('t.coord')::uuid);
select public.rpc_vincular_cuenta((select id from public.perfiles where nombre = 'Rosa Ventas'), 'rosa.v@refri.test');
reset role;
do $$
begin
  if (select rol from public.perfiles where auth_id = current_setting('t.rosa')::uuid) <> 'ventas' then
    raise exception '5a · La cuenta no quedó vinculada a la ficha con rol de Ventas.';
  end if;
  if (select count(*) from public.perfiles where correo = 'rosa.v@refri.test' and activo and auth_id is null) > 0 then
    raise exception '5b · La ficha automática vacía quedó activa.';
  end if;
  raise notice '5 · vinculación de cuenta: correcta';
end $$;

-- 6. Avisos: cada quien ve solo los suyos; la app no puede crearlos ------------
select public.fn_avisar(array[(select id from public.perfiles where auth_id = current_setting('t.luis')::uuid),
                              (select id from public.perfiles where auth_id = current_setting('t.coord')::uuid)],
                        'prueba', 'Aviso de prueba', 'Cuerpo', null);
select public.banco_como(current_setting('t.luis')::uuid);
do $$
declare v_otro bigint;
begin
  if (select count(*) from public.notificaciones) <> 1 then
    raise exception '6a · Luis no ve exactamente su aviso.';
  end if;
  begin
    perform public.fn_avisar(array[public.fn_mi_perfil_id()], 'x', 'x', null, null);
    raise exception '6b · La aplicación pudo llamar fn_avisar directamente.';
  exception when insufficient_privilege then null;
  end;
  raise notice '6 · avisos: cada quien ve los suyos; fn_avisar es interna';
end $$;
-- Intenta marcar como leído un aviso ajeno
reset role;
select set_config('t.aviso_coord', (select n.id::text from public.notificaciones n join public.perfiles p on p.id = n.destinatario_id
                                    where p.auth_id = current_setting('t.coord')::uuid), false);
select public.banco_como(current_setting('t.luis')::uuid);
select public.rpc_marcar_leida(current_setting('t.aviso_coord')::bigint);
reset role;
do $$
begin
  if (select leida_en from public.notificaciones where id = current_setting('t.aviso_coord')::bigint) is not null then
    raise exception '6c · Luis marcó como leído un aviso ajeno.';
  end if;
end $$;

-- 7. Modo prueba: al pasar a operación real, lo de prácticas desaparece --------
select public.banco_como(current_setting('t.coord')::uuid);
do $$
begin
  begin
    perform public.rpc_cambiar_modo('operacion', 'Intento del coordinador');
    raise exception '7a · El coordinador cambió el modo del sistema.';
  exception when raise_exception then
    if sqlerrm like '7a%' then raise; end if;
  end;
end $$;
reset role;
select public.banco_como(current_setting('t.admin')::uuid);
select public.rpc_cambiar_modo('operacion', 'Inicio de operación real');
reset role;
select public.banco_como(current_setting('t.luis')::uuid);
do $$
begin
  if (select count(*) from public.notificaciones) <> 0 then
    raise exception '7b · Los avisos de prácticas siguen visibles en operación real.';
  end if;
  raise notice '7 · modo prueba: solo el admin lo cambia y separa los datos';
end $$;
reset role;
do $$
begin
  if (select count(*) from public.modo_bitacora where modo_nuevo = 'operacion') <> 1 then
    raise exception '7c · El cambio de modo no quedó en bitácora.';
  end if;
end $$;

-- 8. Auditoría: registra los cambios; solo la conducción la ve -----------------
do $$
begin
  if (select count(*) from public.auditoria where tabla = 'perfiles' and accion = 'cambio') = 0 then
    raise exception '8a · Los cambios de perfiles no quedaron auditados.';
  end if;
end $$;
select public.banco_como(current_setting('t.luis')::uuid);
do $$
begin
  if (select count(*) from public.auditoria) <> 0 then
    raise exception '8b · Un ingeniero puede leer la auditoría.';
  end if;
end $$;
reset role;
select public.banco_como(current_setting('t.coord')::uuid);
do $$
begin
  if (select count(*) from public.auditoria) = 0 then
    raise exception '8c · La coordinación no puede leer la auditoría.';
  end if;
  if (select perfil_id from public.auditoria where accion = 'baja' or (despues ->> 'activo') = 'false'
      order by id desc limit 1) is distinct from public.fn_mi_perfil_id() then
    raise exception '8d · La auditoría no registró quién hizo el retiro.';
  end if;
  raise notice '8 · auditoría: registra quién hizo cada cambio; solo la conducción la ve';
end $$;
reset role;

-- 9. Un visitante sin sesión no ve nada ----------------------------------------
select public.banco_como_anonimo();
do $$
begin
  begin
    perform count(*) from public.perfiles;
    raise exception '9a · anon puede leer perfiles.';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.rpc_mi_sesion();
    raise exception '9b · anon puede llamar rpc_mi_sesion.';
  exception when insufficient_privilege then null;
  end;
  raise notice '9 · visitante sin sesión: sin acceso';
end $$;
reset role;
