#!/usr/bin/env bash
# Télécharge les 8 tables de la base bancaire (banque de détail tchèque, 1993-1998, anonymisée).
# Source : PKDD'99 Discovery Challenge (P. Berka, M. Sochorová), copie publique pinnée sur un commit GitHub.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p data
BASE="https://raw.githubusercontent.com/ldaniel/R_Bank_Berka/06f32ce72b1df85eeff8556e0d9878f126c0e82f/data"
for f in account client disp district loan card order trans; do
  [ -s "data/$f.asc" ] && { echo "[skip] $f.asc"; continue; }
  curl -fsSL --retry 3 "$BASE/$f.asc" -o "data/$f.asc"
  echo "[ok] $f.asc ($(wc -l < data/$f.asc) lignes)"
done
