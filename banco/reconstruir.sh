#!/usr/bin/env bash
# Reconstruye la base del banco desde cero: imitación de Supabase + todos los archivos de sql/
# en orden, cada uno en su propia transacción. Se detiene en el primero que falle.
#
# Variables (con sus valores por omisión):
#   PGHOST=localhost  PGPORT=5432  PGUSER=postgres  BANCO_DB=sgp_banco
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$AQUI/.." && pwd)"
export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
DB="${BANCO_DB:-sgp_banco}"

psql -q -X -v ON_ERROR_STOP=1 -d postgres -c "drop database if exists $DB with (force);"
psql -q -X -v ON_ERROR_STOP=1 -d postgres -c "create database $DB;"

echo "▸ banco/00_BANCO_como_supabase.sql"
psql -q -X -v ON_ERROR_STOP=1 -1 -d "$DB" -f "$AQUI/00_BANCO_como_supabase.sql" >/dev/null

for f in $(ls "$RAIZ"/sql/[0-9][0-9]_*.sql | sort); do
  echo "▸ sql/$(basename "$f")"
  if ! psql -X -v ON_ERROR_STOP=1 -1 -d "$DB" -f "$f" > "$AQUI/ultimo.log" 2>&1; then
    echo "✗ Falló sql/$(basename "$f"):"; tail -20 "$AQUI/ultimo.log"; exit 1
  fi
  # Las comprobaciones del archivo se imprimen como avisos (NOTICE)
  grep -E "NOTICE:" "$AQUI/ultimo.log" | sed 's/^.*NOTICE:  /    /' || true
done

echo "✓ Base $DB reconstruida."
