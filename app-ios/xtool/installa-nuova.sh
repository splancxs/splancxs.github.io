#!/bin/bash
# Compila e installa «Recomp 2», l'app iPhone scritta in SwiftUI (app-ios/swiftui), con la sua app Apple Watch, dal PC Windows
# (dentro WSL, con xtool e l'Apple ID gratuito). Ha un identificativo suo (io.github.splancxs.recomp.nuova): convive con l'app
# con il sito dentro, che resta com'è finché la nuova non è completa.
#
#   installa-nuova.sh            iPhone + orologio
#   installa-nuova.sh iphone     solo iPhone (poi va rifatto l'orologio)
#   installa-nuova.sh orologio   solo l'app Watch, già costruita dall'ultima volta
#   installa-nuova.sh watch      ricompila solo l'orologio e rifà l'installazione
#   installa-nuova.sh compila    compila tutto senza installare: per controllare che il codice compili
#   installa-nuova.sh tutto sostituisci   al posto dell'app «Recomp» con il sito dentro (stesso identificativo): vedi sotto
set -euo pipefail
QUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$QUI/../.." && pwd)"
[ -f "$QUI/config.sh" ] || { echo "Manca config.sh: copia config.esempio.sh in config.sh e compilalo."; exit 1; }
. "$QUI/config.sh"
. "$HOME/.local/share/swiftly/env.sh"
COSA="${1:-tutto}"
COME="${2:-}"
if [ "$COME" = sostituisci ]; then
  # SOSTITUISCE l'app «Recomp» con il sito dentro: stesso identificativo, stesso nome, stessa app Watch. I dati dell'app vecchia
  # non passano da soli: prima si esporta il backup da lì e poi si importa nella nuova (Profilo → Importa backup).
  export PHONE_ID=io.github.splancxs.recomp.prova GROUP_ID=group.io.github.splancxs.recomp WATCH_DIR=orologio WATCH_NAME="Recomp"
else
  export PHONE_ID=io.github.splancxs.recomp.nuova GROUP_ID=group.io.github.splancxs.recomp.nuova WATCH_DIR=orologio-nuova WATCH_NAME="Recomp 2"
fi

if [ "$COSA" != compila ]; then
  pkill usbmuxd 2>/dev/null || true
  if [ "$(wslinfo --networking-mode 2>/dev/null || true)" = mirrored ]; then
    export USBMUXD_SOCKET_ADDRESS="127.0.0.1:27015"
  else
    export USBMUXD_SOCKET_ADDRESS="$(ip route list default | awk '{print $3}'):27015"
  fi
  if ! timeout 8 bash -c "exec 3<>/dev/tcp/${USBMUXD_SOCKET_ADDRESS%:*}/27015" 2>/dev/null; then
    echo "Non raggiungo l'iPhone: apri l'app «Apple Devices» su Windows, collega e sblocca l'iPhone."
    exit 1
  fi
  if timeout 30 "$PMD" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q '"ConnectionType": "USB"'; then
    CONN=--usb
  else
    CONN=--network
    echo "Nota: iPhone senza cavo (Wi-Fi): l'app iPhone si installa, ma per l'orologio serve il cavo USB."
  fi
fi

P="$LAVORO/RecompNuova"
APP="$P/xtool/RecompNuova.app"
FIRMATO="$LAVORO/firmato-nuova"
S="$REPO/app-ios/swiftui"

# con l'Apple ID gratuito l'elenco dei dispositivi del team si svuota ogni 7 giorni: l'orologio va rimesso
if [ "$COSA" != iphone ] && [ "$COSA" != compila ]; then
  ELENCO="$("$XTOOL_PATCHATO" ds devices list </dev/null 2>/dev/null || true)"
  if ! printf '%s' "$ELENCO" | grep -q "$WATCH_UDID"; then
    echo "Registro l'orologio sul team (l'elenco dei dispositivi si azzera ogni settimana)…"
    "$XTOOL_PATCHATO" ds devices add --udid "$WATCH_UDID" --name "Apple Watch" </dev/null
  fi
fi

if [ "$COSA" = watch ]; then
  [ -d "$APP" ] || { echo "Prima lancia «installa-nuova.sh» senza argomenti (serve l'app iPhone già costruita)."; exit 1; }
  echo "1/3 Compilo l'app Watch…"
  bash "$QUI/costruisci-orologio.sh"
  echo "2/3 Rifirmo e reinstallo l'app iPhone con l'app Watch nuova…"
  rm -rf "$APP/Watch"; mkdir -p "$APP/Watch"
  cp -R "$LAVORO/$WATCH_DIR/out/RecompWatch.app" "$APP/Watch/"
  rm -rf "$FIRMATO"
  XTOOL_KEEP_SIGNED="$FIRMATO" "$XTOOL_PATCHATO" install $CONN "$APP" </dev/null
  echo "3/3 Installo l'app Watch direttamente sull'orologio…"
  WATCH_UDID="$WATCH_UDID" "$PMD" "$QUI/orologio_installa.py" "$FIRMATO/RecompNuova.app/Watch/RecompWatch.app"
  echo "Fatto: guarda l'orologio."
  exit 0
fi

if [ "$COSA" != orologio ]; then
  echo "1/4 Preparo il progetto…"
  rm -rf "$P/Sources" "$P/Resources"
  mkdir -p "$P/Sources/RecompNuova" "$P/Sources/RecompLive" "$P/Resources"
  cp "$S/"{xtool.yml,Info.plist,RecompLive-Info.plist,RecompLive.entitlements,App.entitlements,Package.swift} "$P/"
  cp "$S/Sources/RecompNuova/"*.swift "$P/Sources/RecompNuova/"
  cp "$REPO/app-ios/native/Shared/RestAttributes.swift" "$REPO/app-ios/native/Watch/Shared/WatchModel.swift" "$P/Sources/RecompNuova/"
  cp "$REPO/app-ios/native/RecompLive/RestLiveActivity.swift" "$REPO/app-ios/native/Shared/RestAttributes.swift" "$P/Sources/RecompLive/"
  # widget della schermata Home: sta nella stessa estensione della Live Activity (legge lo stato salvato nel gruppo condiviso)
  cp "$REPO/app-ios/native/Home/HomeWidget.swift" "$REPO/app-ios/native/Watch/Shared/WatchModel.swift" "$P/Sources/RecompLive/"
  sed -i 's/var body: some Widget { RestLiveActivity() }/var body: some Widget { RestLiveActivity(); RecompHomeWidget() }/' "$P/Sources/RecompLive/RestLiveActivity.swift"
  if [ "$COME" = sostituisci ]; then
    sed -i "s/io.github.splancxs.recomp.nuova/io.github.splancxs.recomp.prova/" "$P/xtool.yml" "$P/Info.plist"
    sed -i "s#<string>recomp2</string>#<string>recomp</string>#; s/Recomp 2/Recomp/" "$P/Info.plist" "$P/RecompLive-Info.plist"
    sed -i "s/group.io.github.splancxs.recomp.nuova/group.io.github.splancxs.recomp/" "$P/App.entitlements" "$P/RecompLive.entitlements"
  fi
  cp "$S/Resources/piano.json" "$P/Resources/"
  cp "$S/Resources/movimenti.json" "$P/Resources/"   # pose del manichino 3D (tools/movimenti.py)
  cp "$REPO/app-ios/resources/icon-1024.png" "$P/Resources/AppIcon.png"

  echo "2/4 Compilo l'app Watch…"
  bash "$QUI/costruisci-orologio.sh"

  echo "3/4 Compilo, firmo e installo l'app iPhone…"
  (cd "$P" && "$XTOOL_STD" dev build </dev/null)
  [ "$COSA" = compila ] && { echo "Compilazione riuscita (nessuna installazione)."; exit 0; }
  rm -rf "$APP/Watch"; mkdir -p "$APP/Watch"
  cp -R "$LAVORO/$WATCH_DIR/out/RecompWatch.app" "$APP/Watch/"
  rm -rf "$FIRMATO"
  XTOOL_KEEP_SIGNED="$FIRMATO" "$XTOOL_PATCHATO" install $CONN "$APP" </dev/null
fi

if [ "$COSA" != iphone ]; then
  echo "4/4 Installo l'app Watch direttamente sull'orologio…"
  W="$FIRMATO/RecompNuova.app/Watch/RecompWatch.app"
  [ -d "$W" ] || { echo "Manca l'app Watch firmata: lancia prima «installa-nuova.sh» senza argomenti."; exit 1; }
  WATCH_UDID="$WATCH_UDID" "$PMD" "$QUI/orologio_installa.py" "$W"
fi

echo
echo "Fatto. Apri «Recomp 2» sull'iPhone: l'orologio riceve i dati da lì."
echo "La firma gratuita scade tra 7 giorni (da oggi: $(date -d '+7 days' '+%d/%m/%Y')): rilancia questo comando prima."
