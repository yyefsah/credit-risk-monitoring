#!/usr/bin/env bash
# Porte qualité : aucun contrôle SQL de gravité 'error' en échec, et résultats attendus non triviaux.
set -euo pipefail
export PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-yacine} PGDATABASE=${PGDATABASE:-bankrisk}
fail=$(psql -Atc "SELECT count(*) FROM dq.result WHERE severity='error' AND NOT passed")
n=$(psql -Atc "SELECT count(*) FROM dq.result")
loans=$(psql -Atc "SELECT count(*) FROM mart.loan_base")
bad=$(psql -Atc "SELECT count(*) FROM mart.loan_base WHERE is_bad")
echo "contrôles=$n erreurs=$fail prêts=$loans défaillants=$bad"
[ "$fail" = 0 ] && [ "$n" -ge 20 ] && [ "$loans" = 682 ] && [ "$bad" = 76 ] && echo "PORTE QUALITÉ OK"
