#!/bin/bash
# Installa Recomp sull'iPhone collegato, con l'app per Apple Watch e Salute, firmata con l'Apple ID gratuito.
# Prima: Xcode → Settings → Accounts con il tuo Apple ID; iPhone collegato col cavo, sbloccato, autorizzato
# e con la Modalità sviluppatore attiva. La firma gratuita dura 7 giorni: per rinnovarla basta rilanciarlo.
# Va lanciato dal Terminale del Mac (la firma usa il portachiavi della tua sessione), dalla cartella del repository:
#   app-ios/installa.sh                 TEAM=XXXXXXXXXX app-ios/installa.sh   (per scegliere il team a mano)
#   app-ios/installa.sh ripeti          reinstalla l'ultima compilazione senza rifarla
# Registro completo in /tmp/recomp-installa.log
set -euo pipefail
cd "$(dirname "$0")"
exec > >(tee /tmp/recomp-installa.log) 2>&1

need() { command -v "$1" >/dev/null 2>&1 || { echo "Manca $1: $2"; exit 1; }; }
need xcodebuild "installa Xcode e aprilo una volta"
need node "installa Node.js (LTS) da https://nodejs.org"

# team personale dell'Apple ID aggiunto in Xcode
TEAM="${TEAM:-$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | grep -m1 -E 'teamID = ' | sed -E 's/.*teamID = "?([A-Z0-9]{10})"?;.*/\1/')}"
[ -n "$TEAM" ] || { echo "Non trovo il tuo team: aggiungi l'Apple ID in Xcode → Settings → Accounts"; exit 1; }
echo "Team: $TEAM"

# iPhone collegato
xcrun devicectl list devices --json-output /tmp/recomp-devices.json >/dev/null
DEVICE=$(node -e '
  const d = require("/tmp/recomp-devices.json").result.devices
    .filter((x) => x.hardwareProperties && x.hardwareProperties.deviceType === "iPhone" && x.connectionProperties && x.connectionProperties.pairingState === "paired");
  if (!d.length) { console.error("Nessun iPhone collegato e autorizzato: collegalo col cavo, sbloccalo e tocca Autorizza"); process.exit(1); }
  console.log(d[0].identifier);')
echo "iPhone: $DEVICE"

# Apple Watch visto da Xcode: serve il Bluetooth sul Mac e la Modalità sviluppatore sull'orologio.
# Se c'è, Xcode lo registra sull'Apple ID: senza, l'orologio rifiuta l'app («impossibile verificarne l'integrità»).
read -r WATCH_UDID WATCH_ID <<<"$(node -e '
  const d = require("/tmp/recomp-devices.json").result.devices
    .filter((x) => x.hardwareProperties && x.hardwareProperties.platform === "watchOS");
  if (d.length) console.log(d[0].hardwareProperties.udid, d[0].identifier);')"
if [ -n "${WATCH_UDID:-}" ]; then echo "Apple Watch: $WATCH_UDID"; else echo "Apple Watch non visto da Xcode: installo solo l'iPhone."; fi

APP=build-device/Build/Products/Release-iphoneos/App.app
# «app-ios/installa.sh ripeti»: reinstalla l'ultima compilazione senza rifarla (per esempio dopo aver liberato un posto)
if [ "${1:-}" = ripeti ] && [ -d "$APP" ]; then
  echo "Reinstallo l'ultima compilazione…"
else
  echo "1/4 Preparo il progetto…"
  WATCH=1 bash prepara.sh >/dev/null

  if [ -n "${WATCH_UDID:-}" ]; then
    echo "2/4 Registro l'orologio sul tuo Apple ID e compilo la sua app…"
    xcodebuild -project ios/App/App.xcodeproj -scheme RecompWatch -configuration Release -destination "id=$WATCH_UDID" \
      -derivedDataPath build-device -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
      DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
      -quiet build
  fi

  echo "3/4 Compilo e firmo (la prima volta Xcode crea i certificati: qualche minuto)…"
  xcodebuild -project ios/App/App.xcodeproj -scheme App -configuration Release -destination "generic/platform=iOS" \
    -derivedDataPath build-device -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
    DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic \
    -quiet build
fi

echo "4/4 Installo sull'iPhone…"
xcrun devicectl device install app --device "$DEVICE" "$APP"

if [ -n "${WATCH_UDID:-}" ]; then
  # il permesso dell'app Watch deve elencare l'orologio, altrimenti l'orologio la rifiuta
  if security cms -D -i "$APP/Watch/RecompWatch.app/embedded.mobileprovision" 2>/dev/null | grep -q "$WATCH_UDID"; then
    echo "Installo sull'orologio (tienilo sbloccato e vicino)…"
    xcrun devicectl device install app --device "$WATCH_ID" "$APP/Watch/RecompWatch.app" \
      || echo "Installazione diretta non riuscita: sull'iPhone apri l'app Watch → Recomp → Installa."
  else
    echo "Attenzione: il permesso dell'app Watch non contiene ancora l'orologio."
  fi
fi
echo
echo "Fatto! Recomp è sull'iPhone. L'app per l'orologio si installa da sola (o dall'app Watch → Recomp → Installa)."
echo "Al primo avvio: Impostazioni → Generali → VPN e gestione dispositivi → il tuo Apple ID → Autorizza."
