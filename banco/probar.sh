#!/usr/bin/env bash
# Reconstruye el banco y corre cada prueba de pruebas/ dentro de una transacción que se
# deshace al final, para que una prueba no contamine a la siguiente.
# Una prueba falla lanzando una excepción (raise exception) con un mensaje que nombra lo que falta.
set -euo pipefail

AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(cd "$AQUI/.." && pwd)"
export PGHOST="${PGHOST:-localhost}" PGPORT="${PGPORT:-5432}" PGUSER="${PGUSER:-postgres}"
DB="${BANCO_DB:-sgp_banco}"

"$AQUI/reconstruir.sh"
echo
fallas=0; total=0
for f in $(ls "$RAIZ"/pruebas/*.sql | sort); do
  total=$((total+1))
  if salida=$( { echo "begin;"; cat "$f"; echo "rollback;"; } | psql -X -q -v ON_ERROR_STOP=1 -d "$DB" 2>&1 ); then
    echo "✓ $(basename "$f")"
    echo "$salida" | grep -E "NOTICE:" | sed 's/^.*NOTICE:  /    /' || true
  else
    fallas=$((fallas+1))
    echo "✗ $(basename "$f")"
    echo "$salida" | grep -E "ERROR|NOTICE" | sed 's/^/    /'
  fi
done
echo
echo "Pruebas: $((total-fallas)) de $total correctas."
[ "$fallas" -eq 0 ]
