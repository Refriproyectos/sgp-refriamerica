#!/usr/bin/env bash
# =============================================================================
# Respaldo de la base del SGP, con prueba de restauración.
#
# 1. Vuelca el esquema public (estructura + datos) y las cuentas de acceso (auth.users,
#    auth.identities, solo datos) en formato custom de pg_dump.
# 2. Cuenta las filas de cada tabla de public en producción.
# 3. RESTAURA el volcado de public en una base vacía que imita Supabase y compara los conteos.
#    Un respaldo que no se pudo restaurar no es un respaldo: si no coincide, el proceso falla.
# 4. Opcional: sube los archivos a Google Drive con rclone y aplica la retención
#    (diarios por 31 días; el del día 1 de cada mes, por 400 días).
#
# Variables:
#   ORIGEN_URL         cadena de conexión a la base de producción (secreto; nunca en el código)
#   RESTAURAR_URL      cadena a un servidor PostgreSQL vacío para la prueba (base de mantenimiento)
#   PG_BIN             carpeta de los binarios de PostgreSQL (misma versión que producción o mayor)
#   SALIDA             carpeta donde se dejan los archivos (por omisión ./respaldos)
#   RCLONE_DESTINO     remoto de rclone (ej. "sgp:"); si está vacío, no se sube nada
# =============================================================================
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
: "${ORIGEN_URL:?Falta ORIGEN_URL}"
: "${RESTAURAR_URL:?Falta RESTAURAR_URL}"
PG_BIN="${PG_BIN:-$(dirname "$(command -v pg_dump)")}"
SALIDA="${SALIDA:-./respaldos}"
FECHA="$(TZ=America/Caracas date +%Y-%m-%d_%H%M)"
BASE="sgp_${FECHA}"
mkdir -p "$SALIDA"

psql_() { "$PG_BIN/psql" -X -q -v ON_ERROR_STOP=1 "$@"; }

conteos() {   # imprime "tabla;filas" de cada tabla de public, ordenado
  local url="$1" consulta
  consulta=$(psql_ "$url" -Atc "select string_agg(format('select %L, count(*) from public.%I', tablename, tablename), ' union all ' order by tablename) from pg_tables where schemaname = 'public'")
  [ -z "$consulta" ] && return 0
  psql_ "$url" -At -F ';' -c "$consulta order by 1"
}

echo "▸ Versión de las herramientas: $("$PG_BIN/pg_dump" --version)"

echo "▸ 1/4 Volcado de public"
"$PG_BIN/pg_dump" "$ORIGEN_URL" --format=custom --schema=public --no-owner --no-privileges \
  --file="$SALIDA/${BASE}_public.dump"

echo "▸ 1/4 Volcado de cuentas de acceso (auth.users, auth.identities)"
"$PG_BIN/pg_dump" "$ORIGEN_URL" --format=custom --data-only \
  --table=auth.users --table=auth.identities --file="$SALIDA/${BASE}_auth.dump" \
  || echo "  ⚠ No se pudieron volcar las cuentas (se continúa con public)."

echo "▸ 2/4 Conteo de filas en producción"
conteos "$ORIGEN_URL" > "$SALIDA/${BASE}_conteos.txt"
cat "$SALIDA/${BASE}_conteos.txt" | sed 's/^/    /'

echo "▸ 3/4 Prueba de restauración"
psql_ "$RESTAURAR_URL" -c "drop database if exists sgp_restaurado with (force)" -c "create database sgp_restaurado"
DESTINO_URL="$(echo "$RESTAURAR_URL" | sed -E 's#/[^/?]*(\?|$)#/sgp_restaurado\1#')"
psql_ "$DESTINO_URL" -f "$AQUI/00_BANCO_como_supabase.sql" >/dev/null
# El volcado trae su propio esquema public: se parte de uno vacío para que la restauración
# reproduzca exactamente lo de producción.
psql_ "$DESTINO_URL" -c "drop schema public cascade"
# Primero las tablas y los datos; las restricciones al final, después de crear en la
# imitación de auth.users las cuentas a las que apuntan los perfiles.
"$PG_BIN/pg_restore" --exit-on-error --dbname="$DESTINO_URL" --no-owner --no-privileges --section=pre-data "$SALIDA/${BASE}_public.dump"
"$PG_BIN/pg_restore" --exit-on-error --dbname="$DESTINO_URL" --no-owner --no-privileges --section=data --disable-triggers "$SALIDA/${BASE}_public.dump"
psql_ "$DESTINO_URL" -c "insert into auth.users (id) select distinct auth_id from public.perfiles where auth_id is not null on conflict do nothing"
"$PG_BIN/pg_restore" --exit-on-error --dbname="$DESTINO_URL" --no-owner --no-privileges --section=post-data "$SALIDA/${BASE}_public.dump"

conteos "$DESTINO_URL" > "$SALIDA/${BASE}_conteos_restaurado.txt"
if ! diff -q "$SALIDA/${BASE}_conteos.txt" "$SALIDA/${BASE}_conteos_restaurado.txt" >/dev/null; then
  echo "✗ La restauración NO reproduce la base:"; diff "$SALIDA/${BASE}_conteos.txt" "$SALIDA/${BASE}_conteos_restaurado.txt" || true
  exit 1
fi
echo "✓ Restauración comprobada: $(wc -l < "$SALIDA/${BASE}_conteos.txt") tablas con los mismos conteos."
rm -f "$SALIDA/${BASE}_conteos_restaurado.txt"
psql_ "$RESTAURAR_URL" -c "drop database sgp_restaurado with (force)"

if [ -n "${RCLONE_DESTINO:-}" ]; then
  echo "▸ 4/4 Subida a Google Drive"
  rclone copy "$SALIDA" "$RCLONE_DESTINO" --include "${BASE}_*" --drive-chunk-size 16M
  echo "▸ 4/4 Retención: diarios 31 días, mensuales (día 01) 400 días"
  rclone delete "$RCLONE_DESTINO" --min-age 31d --filter "- sgp_????-??-01_*" --filter "+ sgp_*" --filter "- *"
  rclone delete "$RCLONE_DESTINO" --min-age 400d --filter "+ sgp_????-??-01_*" --filter "- *"
  rclone lsl "$RCLONE_DESTINO" --include "${BASE}_*"
else
  echo "▸ 4/4 Sin destino de Drive configurado: los archivos quedan en $SALIDA"
fi
echo "✓ Respaldo ${BASE} terminado."
