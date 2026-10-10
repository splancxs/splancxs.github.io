#!/bin/bash
# Prova: applica le modifiche a una copia pulita di xtool in /tmp e controlla che tutte vadano a buon fine.
set -euo pipefail
QUI="$(cd "$(dirname "$0")" && pwd)"
rm -rf /tmp/xtool-pulito
git clone -q https://github.com/xtool-org/xtool /tmp/xtool-pulito
git -C /tmp/xtool-pulito checkout -q d802c71
python3 "$QUI/patches/applica-patch.py" /tmp/xtool-pulito
echo "--- seconda esecuzione (deve dire «già applicata» ovunque)"
python3 "$QUI/patches/applica-patch.py" /tmp/xtool-pulito | grep -c "già applicata"
