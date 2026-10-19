#!/bin/bash
# Compila e installa Recomp sull'iPhone e sull'Apple Watch dal PC Windows (dentro WSL), con xtool e un Apple ID gratuito.
# La firma gratuita dura 7 giorni: per rinnovarla basta rilanciare questo comando.
#
#   installa.sh            iPhone + orologio (consigliato)
#   installa.sh iphone     solo iPhone (poi però va rifatto anche l'orologio: l'iPhone «dimentica» l'app Watch)
#   installa.sh orologio   solo l'app Watch, già costruita dall'ultima volta
#   installa.sh watch      giro veloce dopo aver cambiato il codice dell'app Watch: ricompila solo l'orologio
#   installa.sh compila    compila tutto senza installare (iPhone non collegato): per controllare che il codice compili
#
# ORDINE OBBLIGATO: prima l'app iPhone, poi l'app Watch direttamente sull'orologio. Ogni volta che si reinstalla
# l'app iPhone, l'iPhone ritiene l'app Watch non installata (WCSession: appInstalled NO) finché non si reinstalla l'orologio.
# Servono: iPhone collegato al PC e sbloccato, app «Apple Devices» di Windows aperta, orologio sbloccato e al polso.
set -euo pipefail
QUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$QUI/../.." && pwd)"
[ -f "$QUI/config.sh" ] || { echo "Manca config.sh: copia config.esempio.sh in config.sh e compilalo."; exit 1; }
. "$QUI/config.sh"
. "$HOME/.local/share/swiftly/env.sh"
COSA="${1:-tutto}"

if [ "$COSA" != compila ]; then
  # l'iPhone si raggiunge attraverso il servizio Apple di Windows (porta 27015), non con usbipd (dà timeout nell'installazione)
  pkill usbmuxd 2>/dev/null || true
  if [ "$(wslinfo --networking-mode 2>/dev/null || true)" = mirrored ]; then
    # rete «mirrored» (.wslconfig): Windows e Linux condividono la rete, il servizio Apple è su 127.0.0.1, niente porta.ps1
    export USBMUXD_SOCKET_ADDRESS="127.0.0.1:27015"
  else
    export USBMUXD_SOCKET_ADDRESS="$(ip route list default | awk '{print $3}'):27015"
  fi
  if ! timeout 8 bash -c "exec 3<>/dev/tcp/${USBMUXD_SOCKET_ADDRESS%:*}/27015" 2>/dev/null; then
    echo "Non raggiungo l'iPhone: apri l'app «Apple Devices» su Windows, collega e sblocca l'iPhone,"
    echo "poi (una tantum, o dopo un riavvio del PC) lancia windows/porta.ps1 da PowerShell come amministratore."
    exit 1
  fi

  # con il Wi-Fi attivo l'iPhone compare due volte (rete e USB) e xtool chiederebbe quale usare: scelgo io, USB se c'è il cavo
  if timeout 30 "$PMD" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q '"ConnectionType": "USB"'; then
    CONN=--usb
  else
    CONN=--network
    echo "Nota: iPhone senza cavo (Wi-Fi): l'app iPhone si installa, ma per l'orologio serve il cavo USB."
  fi
fi

P="$LAVORO/Recomp"
APP="$P/xtool/RecompProva.app"

# Con l'Apple ID gratuito l'elenco dei dispositivi del team si svuota ogni 7 giorni (resta solo l'iPhone, che xtool rimette da solo).
# Senza l'orologio nel team il profilo dell'app Watch non vale: «A valid provisioning profile for this executable was not found».
if [ "$COSA" != iphone ] && [ "$COSA" != compila ]; then
  ELENCO="$("$XTOOL_PATCHATO" ds devices list </dev/null 2>/dev/null || true)"
  if ! printf '%s' "$ELENCO" | grep -q "$WATCH_UDID"; then
    echo "Registro l'orologio sul team (l'elenco dei dispositivi si azzera ogni settimana)…"
    "$XTOOL_PATCHATO" ds devices add --udid "$WATCH_UDID" --name "Apple Watch" </dev/null
  fi
fi

if [ "$COSA" = watch ]; then
  # giro veloce per provare modifiche all'app Watch: ricompila solo l'orologio, ricorda l'app iPhone già costruita,
  # la rifirma con l'app Watch nuova e rifà l'installazione (iPhone e poi orologio, nell'ordine obbligato)
  [ -d "$APP" ] || { echo "Prima lancia «installa.sh» senza argomenti (serve l'app iPhone già costruita)."; exit 1; }
  echo "1/3 Compilo l'app Watch…"
  bash "$QUI/costruisci-orologio.sh"
  echo "2/3 Rifirmo e reinstallo l'app iPhone con l'app Watch nuova…"
  rm -rf "$APP/Watch"; mkdir -p "$APP/Watch"
  cp -R "$LAVORO/orologio/out/RecompWatch.app" "$APP/Watch/"
  rm -rf "$LAVORO/firmato"
  XTOOL_KEEP_SIGNED="$LAVORO/firmato" "$XTOOL_PATCHATO" install $CONN "$APP" </dev/null
  echo "3/3 Installo l'app Watch direttamente sull'orologio…"
  WATCH_UDID="$WATCH_UDID" "$PMD" "$QUI/orologio_installa.py" "$LAVORO/firmato/RecompProva.app/Watch/RecompWatch.app"
  echo "Fatto: guarda l'orologio (apri Recomp sull'iPhone se resta su «Apri Recomp sull'iPhone»)."
  exit 0
fi

if [ "$COSA" != orologio ]; then
  echo "1/4 Preparo il progetto…"
  mkdir -p "$P/Sources/RecompProva" "$P/Sources/RecompLive" "$P/Resources"
  cp "$QUI/progetto/"{xtool.yml,Info.plist,RecompLive-Info.plist,RecompLive.entitlements,App.entitlements} "$P/"
  sed "s#@NPM@#$NPM_CAP#g" "$QUI/progetto/Package.swift.modello" > "$P/Package.swift"
  cp "$QUI/progetto/RecompProvaApp.swift" "$P/Sources/RecompProva/"
  cp "$REPO/app-ios/native/App/"{NativeTabsPlugin,RestActivityPlugin,HealthPlugin,WatchBridgePlugin}.swift "$P/Sources/RecompProva/"
  cp "$REPO/app-ios/native/Shared/RestAttributes.swift" "$P/Sources/RecompProva/"
  cp "$REPO/app-ios/native/RecompLive/RestLiveActivity.swift" "$REPO/app-ios/native/Shared/RestAttributes.swift" "$P/Sources/RecompLive/"
  # widget della schermata Home: sta nella stessa estensione della Live Activity (legge lo stato salvato nel gruppo condiviso)
  cp "$REPO/app-ios/native/Home/HomeWidget.swift" "$REPO/app-ios/native/Watch/Shared/WatchModel.swift" "$P/Sources/RecompLive/"
  sed -i 's/var body: some Widget { RestLiveActivity() }/var body: some Widget { RestLiveActivity(); RecompHomeWidget() }/' "$P/Sources/RecompLive/RestLiveActivity.swift"
  cp "$QUI/progetto/capacitor.config.json" "$P/Resources/"
  cp "$REPO/app-ios/resources/icon-1024.png" "$P/Resources/AppIcon.png"
  rm -rf "$P/Resources/public"; mkdir -p "$P/Resources/public"
  cp "$REPO/index.html" "$REPO/manifest.webmanifest" "$P/Resources/public/"
  cp -R "$REPO/assets" "$P/Resources/public/"

  echo "2/4 Compilo l'app Watch…"
  bash "$QUI/costruisci-orologio.sh"

  echo "3/4 Compilo, firmo e installo l'app iPhone…"
  (cd "$P" && "$XTOOL_STD" dev build </dev/null)
  [ "$COSA" = compila ] && { echo "Compilazione riuscita (nessuna installazione)."; exit 0; }
  rm -rf "$APP/Watch"; mkdir -p "$APP/Watch"
  cp -R "$LAVORO/orologio/out/RecompWatch.app" "$APP/Watch/"
  rm -rf "$LAVORO/firmato"
  XTOOL_KEEP_SIGNED="$LAVORO/firmato" "$XTOOL_PATCHATO" install $CONN "$APP" </dev/null
fi

if [ "$COSA" != iphone ]; then
  echo "4/4 Installo l'app Watch direttamente sull'orologio…"
  W="$LAVORO/firmato/RecompProva.app/Watch/RecompWatch.app"
  [ -d "$W" ] || { echo "Manca l'app Watch firmata: lancia prima «installa.sh» senza argomenti."; exit 1; }
  WATCH_UDID="$WATCH_UDID" "$PMD" "$QUI/orologio_installa.py" "$W"
fi

echo
echo "Fatto. Apri Recomp sull'iPhone: l'orologio riceve i dati da lì."
echo "La firma gratuita scade tra 7 giorni (da oggi: $(date -d '+7 days' '+%d/%m/%Y')): rilancia questo comando prima."
