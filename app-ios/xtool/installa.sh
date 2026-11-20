#!/bin/bash
# Compila e installa Recomp (l'app iPhone in SwiftUI, app-ios/swiftui) con la sua app Apple Watch dal PC Windows,
# dentro WSL, con xtool e l'Apple ID gratuito. La firma gratuita dura 7 giorni: per rinnovarla basta rilanciarlo.
#
#   installa.sh            compila quello che è cambiato e installa iPhone + orologio
#   installa.sh orologio   rifà solo l'installazione sull'orologio, con l'app già pronta dall'ultima volta
#   installa.sh compila    compila senza installare (senza telefono): per controllare che il codice compili
#
# Ordine obbligato: prima l'app iPhone, poi l'app Watch direttamente sull'orologio. Reinstallando l'app iPhone, l'iPhone
# dimentica l'app Watch finché non si reinstalla anche quella: per questo si fanno sempre tutte e due.
set -euo pipefail
QUI="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$QUI/../.." && pwd)"
[ -f "$QUI/config.sh" ] || { echo "Manca config.sh: copia config.esempio.sh in config.sh e compilalo."; exit 1; }
. "$QUI/config.sh"
. "$HOME/.local/share/swiftly/env.sh"
COSA="${1:-tutto}"
case "$COSA" in tutto|orologio|compila) ;; *) echo "Uso: installa.sh [orologio|compila]"; exit 1 ;; esac
export PHONE_ID=io.github.splancxs.recomp.prova   # identificativo dell'app (xtool con l'Apple ID gratuito aggiunge «XTL-…»)

P="$LAVORO/RecompNuova"          # il progetto copiato dentro Linux: lì si compila molto più in fretta che da /mnt/c
APP="$P/xtool/RecompNuova.app"
FIRMATO="$LAVORO/firmato"        # l'app firmata dall'ultima installazione (serve a «orologio»)
S="$REPO/app-ios/swiftui"
N="$REPO/app-ios/native"

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
  # serve il cavo: in Wi-Fi l'installazione dell'iPhone si blocca e l'orologio non si installa
  if ! timeout 30 "$PMD" -m pymobiledevice3 usbmux list 2>/dev/null | grep -q '"ConnectionType": "USB"'; then
    echo "L'iPhone non è collegato col cavo (lo vedo solo in Wi-Fi): collegalo col cavo, sbloccalo e rilancia."
    exit 1
  fi
  # prima di toccare l'app, i backup automatici dell'iPhone passano sul PC (se in config.sh c'è BACKUP_DIR)
  if [ -n "${BACKUP_DIR:-}" ]; then
    "$PMD" "$QUI/copia_backup.py" "$PHONE_ID" "$BACKUP_DIR" || echo "Backup: non sono riuscito a copiarli (vado avanti)."
  fi
  # con l'Apple ID gratuito l'elenco dei dispositivi del team si svuota ogni 7 giorni: l'orologio va rimesso
  if ! "$XTOOL_PATCHATO" ds devices list </dev/null 2>/dev/null | grep -q "$WATCH_UDID"; then
    echo "Registro l'orologio sul team (l'elenco dei dispositivi si azzera ogni settimana)…"
    "$XTOOL_PATCHATO" ds devices add --udid "$WATCH_UDID" --name "Apple Watch" </dev/null
  fi
fi

if [ "$COSA" != orologio ]; then
  echo "1/4 Preparo il progetto…"
  # tutto in una cartella d'appoggio, poi rsync confronta il contenuto e copia solo i file cambiati: gli altri restano
  # identici (anche la data), così Swift ricompila solo quello che serve
  T="$LAVORO/appoggio"
  rm -rf "$T"
  mkdir -p "$T/Sources/RecompNuova" "$T/Sources/RecompLive" "$T/Resources" "$P"
  cp "$S/"{xtool.yml,Info.plist,RecompLive-Info.plist,RecompLive.entitlements,App.entitlements,Package.swift} "$T/"
  cp "$S/Sources/RecompNuova/"*.swift "$N/Shared/RestAttributes.swift" "$N/Watch/Shared/WatchModel.swift" "$T/Sources/RecompNuova/"
  # Live Activity e widget della schermata Home stanno nella stessa estensione
  cp "$N/RecompLive/RestLiveActivity.swift" "$N/Home/HomeWidget.swift" "$N/Shared/RestAttributes.swift" "$N/Watch/Shared/WatchModel.swift" "$T/Sources/RecompLive/"
  cp "$S/Resources/piano.json" "$S/Resources/movimenti.json" "$T/Resources/"
  cp "$REPO/app-ios/resources/icon-1024.png" "$T/Resources/AppIcon.png"
  rsync -rc --delete "$T/Sources/" "$P/Sources/"
  rsync -rc --delete "$T/Resources/" "$P/Resources/"
  rsync -c "$T/"{xtool.yml,Info.plist,RecompLive-Info.plist,RecompLive.entitlements,App.entitlements,Package.swift} "$P/"

  echo "2/4 App Watch…"
  bash "$QUI/costruisci-orologio.sh"   # si ricompila solo se il suo codice è cambiato

  echo "3/4 Compilo, firmo e installo l'app iPhone…"
  (cd "$P" && "$XTOOL_STD" dev build </dev/null)
  python3 "$QUI/genera_appintents.py" "$APP"
  [ "$COSA" = compila ] && { echo "Compilazione riuscita (nessuna installazione)."; exit 0; }
  rm -rf "$APP/Watch"; mkdir -p "$APP/Watch"
  cp -R "$LAVORO/orologio/out/RecompWatch.app" "$APP/Watch/"
  rm -rf "$FIRMATO"
  XTOOL_KEEP_SIGNED="$FIRMATO" "$XTOOL_PATCHATO" install --usb "$APP" </dev/null
fi

echo "4/4 Installo l'app Watch direttamente sull'orologio…"
W="$FIRMATO/RecompNuova.app/Watch/RecompWatch.app"
[ -d "$W" ] || { echo "Manca l'app Watch firmata: lancia prima installa.sh senza argomenti."; exit 1; }
# «Coordinator found … process-scoped»: appena installata l'app iPhone, iOS prova da solo a mettere l'app Watch
# sull'orologio (e con il profilo gratuito fallisce); finché quel tentativo non si chiude, l'orologio rifiuta il nostro.
# Non si può fermare (servirebbe togliere l'app Watch da dentro l'app iPhone, che però tiene il collegamento tra i due):
# si riprova in silenzio ogni 5 secondi, per un minuto al massimo, e l'errore si mostra solo se non passa mai
REG="$LAVORO/orologio.log"
for prova in $(seq 1 12); do
  set +e
  WATCH_UDID="$WATCH_UDID" "$PMD" "$QUI/orologio_installa.py" "$W" >"$REG" 2>&1
  ESITO=$?
  set -e
  if [ "$ESITO" -eq 0 ]; then cat "$REG"; break; fi
  if [ "$prova" -lt 12 ] && grep -q "Coordinator found" "$REG"; then
    [ "$prova" -eq 1 ] && echo "L'orologio sta finendo un tentativo di iOS: aspetto che si liberi…"
    sleep 5
  else
    cat "$REG"
    exit "$ESITO"
  fi
done

echo
echo "Fatto. Apri Recomp sull'iPhone: l'orologio riceve i dati da lì."
echo "La firma gratuita scade tra 7 giorni (da oggi: $(date -d '+7 days' '+%d/%m/%Y')): rilancia questo comando prima."
