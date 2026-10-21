-- Huella del esquema: un md5 por objeto (tablas, columnas, funciones, políticas,
-- disparadores, vistas, tipos). Se corre en producción y en el banco; si las dos listas
-- difieren, la diferencia dice exactamente qué objeto no coincide.
--
-- Uso:  psql -At -f banco/CONSULTA_huella_del_esquema.sql > huella.csv
with objetos as (
  -- tablas y sus columnas
  select 'tabla' as tipo, c.table_name as nombre,
         string_agg(c.column_name || ':' || c.data_type || ':' || c.is_nullable || ':' ||
                    coalesce(c.column_default, ''), ',' order by c.ordinal_position) as definicion
  from information_schema.columns c
  where c.table_schema = 'public'
  group by c.table_name
  union all
  -- funciones (firma + cuerpo + seguridad)
  select 'funcion', p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f' and p.proname not like 'banco\_%'
  union all
  -- políticas RLS
  select 'politica', tablename || '.' || policyname,
         permissive || ':' || array_to_string(roles, ',') || ':' || cmd || ':' ||
         coalesce(qual, '') || ':' || coalesce(with_check, '')
  from pg_policies where schemaname = 'public'
  union all
  -- disparadores
  select 'disparador', c.relname || '.' || t.tgname, pg_get_triggerdef(t.oid)
  from pg_trigger t join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('public', 'auth') and not t.tgisinternal
  union all
  -- vistas
  select 'vista', viewname, definition from pg_views where schemaname = 'public'
  union all
  -- tipos enumerados
  select 'enum', t.typname, string_agg(e.enumlabel, ',' order by e.enumsortorder)
  from pg_type t join pg_enum e on e.enumtypid = t.oid
  join pg_namespace n on n.oid = t.typnamespace
  where n.nspname = 'public' group by t.typname
)
select tipo || ';' || nombre || ';' || md5(definicion)
from objetos order by tipo, nombre;
