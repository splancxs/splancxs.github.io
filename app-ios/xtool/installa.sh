#!/bin/bash
# Compila e installa Recomp (l'app iPhone in SwiftUI, app-ios/swiftui) con la sua app Apple Watch dal PC Windows,
# dentro WSL, con xtool e l'Apple ID gratuito. La firma gratuita dura 7 giorni: per rinnovarla basta rilanciarlo.
#
#   installa.sh            compila quello che è cambiato e installa iPhone + orologio
#   installa.sh rinnova    come sopra, ma rinnova sempre la firma da Apple (quello che fa /ricarica)
#   installa.sh iphone     solo l'iPhone, per le prove veloci (con debug.sh): l'orologio resta scollegato fino al prossimo «tutto»
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
# «rinnova» = tutto, ma la firma passa sempre da Apple (senza, i profili che valgono ancora più di 6 giorni si riusano)
[ "$COSA" = rinnova ] && { COSA=tutto; RINNOVA=1; }
case "$COSA" in tutto|iphone|orologio|compila) ;; *) echo "Uso: installa.sh [rinnova|iphone|orologio|compila]"; exit 1 ;; esac
export PHONE_ID=io.github.splancxs.recomp.prova   # identificativo dell'app (xtool con l'Apple ID gratuito aggiunge «XTL-…»)

P="$LAVORO/RecompNuova"          # il progetto copiato dentro Linux: lì si compila molto più in fretta che da /mnt/c
APP="$P/xtool/RecompNuova.app"
FIRMATO="$LAVORO/firmato"        # l'app firmata dall'ultima installazione (serve a «orologio»)
S="$REPO/app-ios/swiftui"
N="$REPO/app-ios/native"

if [ "$COSA" != compila ]; then
  pkill usbmuxd 2>/dev/null || true
  # il tunnel del debug (debug.sh prepara) blocca l'installazione al 98%: si ferma qui, poi si rifà «debug.sh prepara»
  if pgrep -f "pymobiledevice3 remote tunneld" >/dev/null; then
    # Recomp aperta sull'iPhone (spesso lanciata dal debug) blocca l'installazione al 98%: la chiudo prima
    timeout 20 "$PMD" -m pymobiledevice3 developer dvt pkill --tunnel '' RecompNuova >/dev/null 2>&1 || true
    pkill -f "pymobiledevice3 remote tunneld" || true
    echo "Ho fermato il tunnel del debug: dopo l'installazione rilancia «debug.ps1 prepara»."
    sleep 2
  fi
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
  # (per le prove veloci, «iphone», si salta se l'ultima copia ha meno di 6 ore)
  TIMBRO="$LAVORO/ultimo-backup"
  if [ -n "${BACKUP_DIR:-}" ]; then
    if [ "$COSA" = iphone ] && [ -n "$(find "$TIMBRO" -mmin -360 2>/dev/null)" ]; then
      echo "Backup: copiati meno di 6 ore fa, salto (prova veloce)."
    elif "$PMD" "$QUI/copia_backup.py" "$PHONE_ID" "$BACKUP_DIR"; then
      touch "$TIMBRO"
    else
      echo "Backup: non sono riuscito a copiarli (vado avanti)."
    fi
  fi
  # con l'Apple ID gratuito l'elenco dei dispositivi del team si svuota ogni 7 giorni: l'orologio va rimesso.
  # Se i server di Apple non rispondono (accesso scaduto o bloccato), si firma senza Apple: stesso certificato e stessi
  # profili dell'ultima installazione, che valgono fino alla loro scadenza (la firma NON si rinnova).
  echo "[${SECONDS}s] controllo l'accesso ad Apple"
  OFFLINE=""; RIUSO=""
  PROF="$FIRMATO/RecompNuova.app/embedded.mobileprovision"
  SCADE="$( [ -f "$PROF" ] && openssl smime -inform der -verify -noverify -in "$PROF" 2>/dev/null \
    | grep -A1 '<key>ExpirationDate</key>' | grep -o '[0-9T:-]*Z' || true)"
  # profili appena rinnovati (valgono ancora più di 6 giorni): si riusano senza chiedere niente ad Apple (−12 s circa).
  # Il rinnovo vero (/ricarica, ogni settimana) passa da Apple come sempre; RINNOVA=1 lo forza.
  if [ "$COSA" != orologio ] && [ -z "${RINNOVA:-}" ] && [ -n "$SCADE" ] \
     && [ $(( $(date -d "$SCADE" +%s) - $(date +%s) )) -gt $(( 6 * 86400 )) ]; then
    OFFLINE="$LAVORO/firmato-prima"; RIUSO=1
    rm -rf "$OFFLINE"; cp -R "$FIRMATO" "$OFFLINE"
    echo "Profili rinnovati da poco (valgono fino al $(date -d "$SCADE" '+%d/%m/%Y %H:%M')): li riuso, niente registrazione da Apple."
  elif DISPOSITIVI="$("$XTOOL_PATCHATO" ds devices list </dev/null 2>/dev/null)"; then
    if ! grep -q "$WATCH_UDID" <<<"$DISPOSITIVI"; then
      echo "Registro l'orologio sul team (l'elenco dei dispositivi si azzera ogni settimana)…"
      "$XTOOL_PATCHATO" ds devices add --udid "$WATCH_UDID" --name "Apple Watch" </dev/null
    fi
  elif [ "$COSA" != orologio ]; then
    if [ -z "$SCADE" ] || [ "$(date -d "$SCADE" +%s)" -le "$(date +%s)" ]; then
      echo "I server di Apple non accettano l'accesso e la firma dell'ultima installazione è scaduta (o manca):"
      echo "rifai l'accesso con «xtool auth login» quando Apple torna a funzionare."
      exit 1
    fi
    OFFLINE="$LAVORO/firmato-prima"
    rm -rf "$OFFLINE"; cp -R "$FIRMATO" "$OFFLINE"
    echo "I server di Apple non accettano l'accesso: firmo senza Apple con la firma attuale (vale fino al $(date -d "$SCADE" '+%d/%m/%Y'))."
  fi
fi

if [ "$COSA" != orologio ]; then
  echo "[${SECONDS}s] 1/4 Preparo il progetto…"
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

  echo "[${SECONDS}s] 2/4 App Watch…"
  bash "$QUI/costruisci-orologio.sh"   # si ricompila solo se il suo codice è cambiato

  echo "[${SECONDS}s] 3/4 Compilo, firmo e installo l'app iPhone…"
  # CONFIG=release: versione ottimizzata (l'isola si ridisegna più in fretta), più lenta da compilare; di base debug
  (cd "$P" && "$XTOOL_STD" dev build -c "${CONFIG:-debug}" </dev/null)
  python3 "$QUI/genera_appintents.py" "$APP"
  echo "[${SECONDS}s] compilata"
  [ "$COSA" = compila ] && { echo "Compilazione riuscita (nessuna installazione)."; exit 0; }
  rm -rf "$APP/Watch"; mkdir -p "$APP/Watch"
  cp -R "$LAVORO/orologio/out/RecompWatch.app" "$APP/Watch/"
  rm -rf "$FIRMATO" "$LAVORO/bundle.txt"   # bundle.txt: l'identificativo salvato da debug.sh, si rilegge
  # ogni passaggio di xtool con i secondi (senza le righe di avanzamento intermedie): si vede dove si perde tempo
  installa_app() {
    XTOOL_OFFLINE="$1" XTOOL_KEEP_SIGNED="$FIRMATO" "$XTOOL_PATCHATO" install --usb "$APP" </dev/null 2>&1 \
      | while IFS= read -r riga; do
          case "$riga" in *%) case "$riga" in *" 0%"|*100%) ;; *) continue ;; esac ;; esac
          [ -n "$riga" ] && printf '[%ss] %s\n' "$SECONDS" "$riga"
        done
  }
  if ! installa_app "$OFFLINE"; then
    # i profili riusati non bastano (per esempio una parte nuova dell'app): si rifà tutto passando da Apple
    [ -n "$RIUSO" ] || exit 1
    echo "[${SECONDS}s] I profili riusati non bastano: registro da Apple e riprovo."
    OFFLINE=""; RIUSO=""
    installa_app ""
  fi
fi

if [ "$COSA" = iphone ]; then
  echo "[${SECONDS}s] Fatto (solo iPhone). L'orologio non riceve i dati finché non rilanci installa.ps1 senza argomenti."
  exit 0
fi

echo "[${SECONDS}s] 4/4 Installo l'app Watch direttamente sull'orologio…"
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
echo "[${SECONDS}s] Fatto. Apri Recomp sull'iPhone: l'orologio riceve i dati da lì."
if [ -n "${RIUSO:-}" ]; then
  echo "Firmata con i profili di questa settimana: la firma scade il $(date -d "$SCADE" '+%d/%m/%Y') (la rinnova il prossimo /ricarica)."
elif [ -n "${OFFLINE:-}" ]; then
  echo "Firmata senza Apple: la firma NON è rinnovata e scade il $(date -d "$SCADE" '+%d/%m/%Y'). Prima di allora rifai"
  echo "l'accesso con «xtool auth login» (quando i server di Apple tornano a funzionare) e rilancia questo comando."
else
  echo "La firma gratuita scade tra 7 giorni (da oggi: $(date -d '+7 days' '+%d/%m/%Y')): rilancia questo comando prima."
fi
