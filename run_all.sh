#!/usr/bin/env bash
# Exécute toute la chaîne : données -> PostgreSQL -> R -> sorties -> tests.
# Prérequis : PostgreSQL (variables PGHOST/PGUSER/PGPASSWORD/PGDATABASE), R >= 4.3 avec les paquets de README.md.
set -euo pipefail
cd "$(dirname "$0")"
export LC_ALL=${LC_ALL:-C.UTF-8} LANG=${LANG:-C.UTF-8} PROJECT_ROOT="$PWD"
echo "== 1/6 Données";            ./scripts/00_download_data.sh
echo "== 2/6 PostgreSQL";         ./sql/run.sh
echo "== 3/6 Extraction + modèle"; Rscript R/01_extract.R; Rscript R/02_model.R > outputs/model_log.txt; tail -n 3 outputs/model_log.txt
echo "== 4/6 Sorties";            Rscript R/03_figures.R; Rscript R/04_export_excel.R; Rscript R/06_export_powerbi.R
(cd R && Rscript -e 'rmarkdown::render("05_dashboard.Rmd", output_file = "../outputs/dashboard_risque_credit.html", quiet = TRUE)')
if command -v soffice >/dev/null 2>&1; then   # recalcul : enregistre les valeurs calculées dans le classeur (lisible partout)
  tmp=$(mktemp -d); soffice --headless --calc --convert-to xlsx --outdir "$tmp" outputs/pilotage_risque_credit.xlsx >/dev/null 2>&1 && cp "$tmp/pilotage_risque_credit.xlsx" outputs/ || echo "(recalcul LibreOffice ignoré)"
fi
echo "== 5/6 Tests R";            Rscript tests/testthat.R
echo "== 6/6 Porte qualité SQL";  ./tests/test_sql_gate.sh
echo "Terminé : voir outputs/"
