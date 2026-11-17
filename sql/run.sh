#!/usr/bin/env bash
# Exécute les scripts SQL dans l'ordre. Variables : PGHOST PGPORT PGUSER PGPASSWORD PGDATABASE (défauts ci-dessous).
set -euo pipefail
cd "$(dirname "$0")/.."
export PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-yacine} PGDATABASE=${PGDATABASE:-bankrisk}
for f in sql/0*.sql; do
  echo ">>> $f"
  psql -v ON_ERROR_STOP=1 -q -f "$f"
done
