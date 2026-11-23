#!/bin/bash
# Controlli sul PC dei conti di Recomp (scambi, porzioni, totali dei giorni), senza telefono: pochi secondi.
# Compila i file dei conti dell'app (gli stessi dell'app, non copie) con app-ios/swiftui/Controlli/main.swift e li prova
# su piano.json. Uso: controlli.sh [--giorni]   (--giorni stampa anche la tabella dei totali di ogni giorno)
set -uo pipefail
QUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$QUI/../.." && pwd)"
. "$QUI/config.sh"
. "$HOME/.local/share/swiftly/env.sh"
S="$REPO/app-ios/swiftui"
D="$LAVORO/controlli"
mkdir -p "$D/Sources/Controlli"
T="$(mktemp -d)"
cp "$S/Sources/RecompNuova/"{Piano,Modelli,Cibi,Aiuti,CibiFuori}.swift "$S/Controlli/main.swift" "$T/"
rsync -rc --delete "$T/" "$D/Sources/Controlli/"   # solo i file cambiati: Swift ricompila il minimo
rm -rf "$T"
[ -f "$D/Package.swift" ] || cat > "$D/Package.swift" <<'EOF'
// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "Controlli", targets: [.executableTarget(name: "Controlli")])
EOF
if ! (cd "$D" && swift build -q 2>&1 | grep -E "error" | sed 's|.*/Sources/Controlli/||' | sort -u | head -20; exit "${PIPESTATUS[0]}"); then
  echo "I controlli non compilano (vedi sopra)."; exit 2
fi
"$D/.build/debug/Controlli" "$S/Resources/piano.json" "$@"
