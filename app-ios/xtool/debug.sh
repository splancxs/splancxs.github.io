#!/bin/bash
# Debug di Recomp sull'iPhone dal PC Windows (dentro WSL), senza Mac: aprire l'app su una schermata, fare uno screenshot,
# leggere il registro dell'app. Serve l'iPhone collegato col cavo, sbloccato, con la Modalità sviluppatore.
#
#   debug.sh prepara            una volta per sessione: tunnel verso l'iPhone (iOS 17+) e immagine sviluppatore di Apple
#   debug.sh apri <cosa>        rilancia l'app su una schermata: oggi, piano, scheda, progressi, profilo, coach, settimana,
#                               pasto:3 (finestra del pasto della fascia 3 di oggi), cibo:3:1, aggiungi:3 (vedi Registro.swift)
#   debug.sh foto <file.png>    screenshot dell'iPhone (percorso Linux, per esempio /mnt/c/Users/…/foto.png)
#   debug.sh registro [secondi] i messaggi «RECOMP» dell'app in diretta (di base 20 secondi)
#   debug.sh prova <azioni> <schermata> [scorri]   MODALITÀ PROVA su una copia dei dati: azioni come «aggiungi:3:parmigiano;
#                               avvia:TA;serie:0:0» (vedi Registro.swift), poi la schermata; scorri = punti verso il basso
#   debug.sh elenco             tutti i testi e i pulsanti della schermata, anche quelli fuori dallo schermo
#   debug.sh controllo          verifica di accessibilità della schermata
#   debug.sh giro [cartella] [--testo] [lista]   giro di controllo su giro.txt (in prova): stato in testo e screenshot di ogni
#                               riga, fogli riassuntivi (foglio_N.jpg); --testo solo lo stato (veloce). Poi l'app torna normale
#   debug.sh stato "<azioni>" <schermata> [scorri] [--foto]   una prova sola: lo stato dell'app in testo (numeri esatti)
#   debug.sh crash              gli ultimi crash di Recomp, con il punto del codice
#   debug.sh isola [secondi]    prova della Dynamic Island: tocchi i pulsanti e si vedono i millisecondi di ogni tocco
#   Alla fine «debug.sh apri oggi» rimette l'app normale (in prova resta la scritta rossa MODALITÀ PROVA).
#   debug.sh chiudi             ferma il tunnel
set -uo pipefail
QUI="$(cd "$(dirname "$0")" && pwd)"
. "$QUI/config.sh"
PHONE_ID=io.github.splancxs.recomp.prova
pkill -x usbmuxd 2>/dev/null || true
if [ "$(wslinfo --networking-mode 2>/dev/null || true)" = mirrored ]; then
  export USBMUXD_SOCKET_ADDRESS="127.0.0.1:27015"
else
  export USBMUXD_SOCKET_ADDRESS="$(ip route list default | awk '{print $3}'):27015"
fi
P3=("$PMD" -m pymobiledevice3)
REG="$LAVORO/tunneld.log"

tunnel_attivo() { pgrep -f "pymobiledevice3 remote tunneld" >/dev/null; }

# l'identificativo vero dell'app: con l'Apple ID gratuito xtool aggiunge «XTL-…» davanti
# (salvato in $LAVORO/bundle.txt: «apps list» costa qualche secondo; installa.sh lo cancella a ogni installazione)
bundle() {
  local f="$LAVORO/bundle.txt"
  if [ ! -s "$f" ]; then
    "${P3[@]}" apps list --type User 2>/dev/null | grep -o "\"[^\"]*$PHONE_ID\"" | head -1 | tr -d '"' > "$f"
  fi
  cat "$f"
}

case "${1:-}" in
  prepara)
    if ! tunnel_attivo; then
      echo "Avvio il tunnel verso l'iPhone…"
      setsid nohup "${P3[@]}" remote tunneld >"$REG" 2>&1 < /dev/null &
      sleep 6
    fi
    tunnel_attivo || { echo "Il tunnel non è partito:"; tail -5 "$REG"; exit 1; }
    echo "Monto l'immagine sviluppatore di Apple (la prima volta la scarica, ~20 MB)…"
    "${P3[@]}" mounter auto-mount --tunnel '' 2>&1 | tail -3
    echo "Pronto: ora «apri», «foto» e «registro»."
    ;;
  apri)
    [ -n "${2:-}" ] || { echo "Uso: debug.sh apri <cosa>"; exit 1; }
    B="$(bundle)"; [ -n "$B" ] || { echo "Recomp non risulta installata sull'iPhone."; exit 1; }
    "${P3[@]}" developer dvt launch --tunnel '' --kill-existing --env "RECOMP_APRI=$2" "$B" 2>&1 | tail -2
    ;;
  prova)
    # prova <azioni> <schermata> [scorri]: l'app riparte in MODALITÀ PROVA (copia dei dati), fa le azioni e apre la schermata
    B="$(bundle)"; [ -n "$B" ] || { echo "Recomp non risulta installata sull'iPhone."; exit 1; }
    "${P3[@]}" developer dvt launch --tunnel '' --kill-existing --env RECOMP_PROVA=1 --env "RECOMP_AZIONI=${2:-}" \
      --env "RECOMP_APRI=${3:-oggi}" --env "RECOMP_SCORRI=${4:-}" "$B" 2>&1 | tail -1
    ;;
  elenco)
    # tutti gli elementi della schermata (testi, pulsanti), anche quelli più in basso
    timeout "${2:-60}" "${P3[@]}" developer accessibility list-items 2>/dev/null \
      | grep -o '"caption": "[^"]*"' | sed 's/"caption": //; s/"//g'
    ;;
  controllo)
    # verifica di accessibilità della schermata (contrasto, testi tagliati, pulsanti piccoli)
    timeout 120 "${P3[@]}" developer accessibility run-audit testTypeContrast testTypeHitRegion testTypeTextClipped \
      testTypeSufficientElementDescription 2>&1 | tail -80
    ;;
  foto)
    OUT="${2:-$LAVORO/foto.png}"
    "${P3[@]}" developer dvt screenshot --tunnel '' "$OUT" 2>&1 | tail -2 && echo "Screenshot: $OUT"
    ;;
  registro)
    echo "Registro di Recomp per ${2:-20} secondi…"
    timeout "${2:-20}" "${P3[@]}" syslog live -m RECOMP 2>/dev/null | grep --line-buffered RECOMP
    true
    ;;
  giro)
    # giro [cartella] [--testo] [lista.txt]: tutte le righe di giro.txt con UNA connessione (giro.py): per ognuna lo stato in
    # testo (nome.txt) e lo screenshot (nome.png; con --testo niente screenshot, molto più veloce), poi i fogli riassuntivi
    OUT="$LAVORO/giro"; LISTA="$QUI/giro.txt"; TESTO=""
    for x in "${@:2}"; do
      case "$x" in --testo|testo) TESTO=--testo ;; *.txt) LISTA="$x" ;; ?*) OUT="$x" ;; esac
    done
    tunnel_attivo || bash "$QUI/debug.sh" prepara >/dev/null 2>&1
    B="$(bundle)"; [ -n "$B" ] || { echo "Recomp non risulta installata sull'iPhone."; exit 1; }
    "$PMD" "$QUI/giro.py" "$B" "$OUT" "$LISTA" $TESTO
    ESITO=$?
    [ -n "$TESTO" ] || "$PMD" "$QUI/montaggio.py" "$OUT" 2>&1 | tail -20
    exit $ESITO
    ;;
  stato)
    # stato "<azioni>" <schermata> [scorri] [--foto]: una prova sola, lo stato dell'app in testo a schermo (pochi secondi)
    tunnel_attivo || bash "$QUI/debug.sh" prepara >/dev/null 2>&1
    B="$(bundle)"; [ -n "$B" ] || { echo "Recomp non risulta installata sull'iPhone."; exit 1; }
    "$PMD" "$QUI/giro.py" "$B" "${FOTO_DIR:-$LAVORO}" --una "${2:-}" "${3:-oggi}" "${@:4}"
    ;;
  isola)
    # isola [secondi]: prova della Dynamic Island. Allenamento finto (in prova) con l'isola accesa: tocchi −15″, +15″,
    # Salta e si vede quanto ci mette ogni tocco e dove gira (estensione o app). Alla fine l'allenamento finto si annulla.
    tunnel_attivo || bash "$QUI/debug.sh" prepara >/dev/null 2>&1
    B="$(bundle)"; [ -n "$B" ] || { echo "Recomp non risulta installata sull'iPhone."; exit 1; }
    "$PMD" "$QUI/giro.py" "$B" "$LAVORO" --isola "${2:-90}"
    ;;
  crash)
    # gli ultimi crash di Recomp sull'iPhone, con la riga del codice dove si è fermata
    mkdir -p "$LAVORO/crash"
    "${P3[@]}" crash pull "$LAVORO/crash" >/dev/null 2>&1
    ULTIMI="$(ls -t "$LAVORO/crash"/RecompNuova* 2>/dev/null | head -3)"
    [ -n "$ULTIMI" ] || { echo "Nessun crash di Recomp sull'iPhone."; exit 0; }
    for f in $ULTIMI; do
      echo "== $(basename "$f")"
      "${P3[@]}" crash parse "$f" 2>/dev/null | grep -E "Exception|Termination|Crashed|RecompNuova " | head -15
    done
    ;;
  chiudi)
    pkill -f "pymobiledevice3 remote tunneld" && echo "Tunnel fermato." || echo "Il tunnel non era attivo."
    ;;
  *)
    sed -n 2,18p "$0"; exit 1 ;;
esac
