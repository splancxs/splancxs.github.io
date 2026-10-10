#!/bin/bash
# Preparazione una tantum di Linux (WSL, Ubuntu) per costruire e installare Recomp con xtool. Come l'ho fatta a mano
# il 10 ottobre 2026: leggila come una ricetta, non lanciarla alla cieca (alcuni passi chiedono te: Apple ID, file Xcode).
#
# Prima, su Windows (PowerShell come amministratore):  wsl --install -d Ubuntu --no-launch ; poi riavvia il PC.
# Serve anche il file Xcode_27.xip (developer.apple.com/download/all, entra con un Apple ID), per esempio in Download.
set -euo pipefail
QUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$QUI/../.." && pwd)"
[ -f "$QUI/config.sh" ] || { cp "$QUI/config.esempio.sh" "$QUI/config.sh"; echo "Ho creato config.sh: correggilo (WATCH_UDID) e rilancia."; exit 1; }
. "$QUI/config.sh"
export DEBIAN_FRONTEND=noninteractive
XIP="${XIP:-/mnt/c/Users/$USER/Downloads/Xcode_27.xip}"   # cambia se il file è altrove

echo "1) programmi di base"
apt-get update -qq
apt-get install -y -qq curl ca-certificates git usbmuxd libimobiledevice-utils build-essential python3-venv python3-dev \
  libz-dev liblzma-dev binutils-gold zip pkg-config xar cpio xz-utils nodejs npm fuse3 libfuse2t64 \
  libgcc-15-dev libpython3-dev libstdc++-15-dev \
  libimobiledevice-dev libimobiledevice-glue-dev libplist-dev libusbmuxd-dev libssl-dev libzip-dev

echo "2) Swift (con Swiftly)"
if ! command -v swift >/dev/null 2>&1 && [ ! -f "$HOME/.local/share/swiftly/env.sh" ]; then
  cd /root && curl -fsSLO "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
  tar zxf "swiftly-$(uname -m).tar.gz" && ./swiftly init --quiet-shell-followup --assume-yes
fi
. "$HOME/.local/share/swiftly/env.sh"

echo "3) xtool (programma normale, per le app iPhone)"
if ! command -v xtool >/dev/null 2>&1; then
  curl -fL "https://github.com/xtool-org/xtool/releases/latest/download/xtool-$(uname -m).AppImage" -o /usr/local/bin/xtool
  chmod +x /usr/local/bin/xtool
fi
echo "   MANUALE: «xtool setup» (modalità Password, con l'Apple ID che usi per Recomp: meglio uno nuovo e vuoto,"
echo "   NON quello di AltStore: xtool vorrebbe revocargli il certificato) e indica $XIP"

echo "4) plugin ufficiali di Capacitor"
mkdir -p "$(dirname "$NPM_CAP")/.." && cd "$(dirname "$(dirname "$NPM_CAP")")"
cp "$REPO/app-ios/package.json" . && npm install --no-audit --no-fund

echo "5) xtool modificato (Apple Watch)"
if [ ! -d "$XTOOL_SRC" ]; then
  git clone https://github.com/xtool-org/xtool "$XTOOL_SRC"
  git -C "$XTOOL_SRC" checkout d802c71
fi
cd "$XTOOL_SRC"
swift build -c release --product xtool || true       # la prima volta scarica anche zsign
python3 "$QUI/patches/applica-patch.py" "$XTOOL_SRC"
swift build -c release --product xtool

echo "6) SDK con anche watchOS (3,7 GB, qualche minuto)"
if [ ! -d "$SDK_OROLOGIO" ]; then
  mkdir -p "$(dirname "$SDK_OROLOGIO")"
  "$XTOOL_PATCHATO" sdk build "$XIP" "$(dirname "$SDK_OROLOGIO")"
  python3 "$QUI/patches/correggi-tbd-watchos.py" "$SDK_OROLOGIO/Developer/Platforms/WatchOS.platform/Developer/SDKs/WatchOS27.0.sdk"
fi

echo "7) pymobiledevice3 (parla con l'orologio attraverso l'iPhone)"
[ -d "$(dirname "$(dirname "$PMD")")" ] || python3 -m venv "$(dirname "$(dirname "$PMD")")"
"$(dirname "$PMD")/pip" install -q pymobiledevice3

cat <<'EOF'

Prepararsi all'orologio (una tantum, con iPhone collegato e orologio sbloccato al polso):
  1. PowerShell come amministratore:  app-ios\xtool\windows\porta.ps1
  2. in Linux:  USBMUXD_SOCKET_ADDRESS="$(ip route list default | awk '{print $3}'):27015" python orologio_sviluppatore.py reveal
     (l'orologio chiede «Autorizza questo computer?» → Autorizza)
  3. sull'orologio: Impostazioni → Privacy e sicurezza → Modalità sviluppatore → attiva, riavvia, conferma
  4. registra l'orologio sull'Apple ID:  $XTOOL_PATCHATO ds devices add --udid "$WATCH_UDID" --name "Apple Watch"
Poi, ogni 7 giorni:  app-ios\xtool\windows\installa.ps1
EOF
