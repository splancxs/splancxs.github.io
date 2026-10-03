#!/bin/bash
# Recomp nel simulatore iPhone di Xcode (solo su Mac, serve Xcode 26 per il Liquid Glass). Dalla cartella del repository:
#   app-ios/simulatore.sh                prepara il progetto, compila e apre l'app (la prima volta qualche minuto)
#   app-ios/simulatore.sh web            dopo una modifica a index.html o assets/: ricopia il sito, ricompila e riapre (meno di un minuto)
#   app-ios/simulatore.sh app            dopo una modifica ai file Swift in app-ios/native (anche l'app Watch): ricompila e riapre
#   app-ios/simulatore.sh vai piano      apre una sezione (oggi, piano, scheda, progressi, profilo, coach)
#   app-ios/simulatore.sh vai piano chiaro   la stessa con il tema chiaro (chiaro, scuro, auto)
#   app-ios/simulatore.sh foto [nome]    screenshot del simulatore in app-ios/screenshots/
#   app-ios/simulatore.sh orologio [nome]   screenshot dell'Apple Watch simulato (abbinato all'iPhone)
#   app-ios/simulatore.sh orologio-vai pasti [TB|fine]   apre l'app Watch su una pagina (allenamento, oggi, pasti);
#                                        con una scheda la avvia, con «fine» chiude l'allenamento di prova
# Modello: SIM="iPhone 17 Pro" app-ios/simulatore.sh   (di base quello già acceso, se no l'iPhone Pro più recente)
set -euo pipefail
cd "$(dirname "$0")"
BUNDLE=io.github.splancxs.recomp
APP=build/Build/Products/Debug-iphonesimulator/App.app
export WATCH=1 # nel simulatore anche l'app per Apple Watch (prepara.sh)

need() { command -v "$1" >/dev/null 2>&1 || { echo "Manca $1: $2" >&2; exit 1; }; }
need xcodebuild "installa Xcode dall'App Store, aprilo una volta e accetta la licenza"
need node "installa Node.js (versione LTS) da https://nodejs.org"
# il Terminale deve usare Xcode e non i soli «strumenti da riga di comando», che non hanno il simulatore
if ! xcrun --find simctl >/dev/null 2>&1; then
  echo "Il Terminale non sta usando Xcode. Lancia (chiede la password del Mac):" >&2
  echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer && sudo xcodebuild -runFirstLaunch" >&2
  exit 1
fi

# simulatore da usare: quello acceso, altrimenti il più recente (preferendo un Pro), oppure quello scelto con SIM
pick() {
  xcrun simctl list devices available -j | SIM="${SIM:-}" node -e '
    let s = "";
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      const all = [];
      for (const [rt, ds] of Object.entries(JSON.parse(s).devices)) {
        const m = rt.match(/iOS-(\d+)-(\d+)/);
        if (m) for (const d of ds) if (d.name.startsWith("iPhone")) all.push({ ...d, v: +m[1] * 100 + +m[2] });
      }
      const want = process.env.SIM;
      const list = want ? all.filter((d) => d.name === want) : all;
      const pro = (d) => (/ Pro$/.test(d.name) ? 1 : 0);
      list.sort((a, b) => (b.state === "Booted") - (a.state === "Booted") || b.v - a.v || pro(b) - pro(a));
      if (!list.length) {
        console.error(want ? `Simulatore "${want}" non trovato (elenco: xcrun simctl list devices)` : "Nessun simulatore iPhone: in Xcode apri Settings > Components e scarica iOS");
        process.exit(1);
      }
      console.log(list[0].udid);
    });'
}

build() {
  local target="-project ios/App/App.xcodeproj"
  [ -d ios/App/App.xcworkspace ] && target="-workspace ios/App/App.xcworkspace"
  echo "Compilo per il simulatore…"
  # niente -sdk: l'app Watch dentro l'app iPhone va compilata per watchOS. Firma «locale» (-): serve al gruppo
  # condiviso tra app Watch e complicazione, e nel simulatore non chiede nessun account.
  xcodebuild $target -scheme App -configuration Debug -destination "id=$UDID" \
    -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO -quiet build
}

# Apple Watch simulato abbinato all'iPhone; se non c'è, abbino il primo libero: di base un SE 3 da 40 mm, come quello
# dell'utente (oppure quello scelto con OROLOGIO="Apple Watch Series 11 (46mm)")
watch_pick() {
  { xcrun simctl list pairs -j; echo '@@'; xcrun simctl list devices available -j; } | PHONE="$UDID" OROLOGIO="${OROLOGIO:-}" node -e '
    let s = "";
    process.stdin.on("data", (d) => (s += d)).on("end", () => {
      const [pairsJ, devsJ] = s.split("@@");
      const pairs = Object.values(JSON.parse(pairsJ).pairs);
      const mine = pairs.find((p) => p.phone.udid === process.env.PHONE);
      if (mine) return console.log(mine.watch.udid);
      const taken = new Set(pairs.map((p) => p.watch.udid));
      const watches = [];
      for (const [rt, ds] of Object.entries(JSON.parse(devsJ).devices)) if (/watchOS/.test(rt)) for (const d of ds) if (!taken.has(d.udid)) watches.push(d);
      const want = process.env.OROLOGIO || "Apple Watch SE 3 (40mm)";
      watches.sort((a, b) => (b.name === want) - (a.name === want));
      if (!watches.length) { console.error("Nessun Apple Watch simulato: in Xcode scarica watchOS da Settings > Components"); process.exit(1); }
      console.log(watches[0].udid + " nuovo");
    });'
}
watch_udid() {
  local w; w=$(watch_pick)
  # abbinamento nuovo: lascio a iPhone e orologio il tempo di sincronizzarsi, altrimenti l'iPhone non vede l'app Watch
  if [[ "$w" == *" nuovo" ]]; then w=${w% nuovo}; xcrun simctl pair "$w" "$UDID" >/dev/null; sleep 20; fi
  echo "$w"
}

watch_run() {
  local wapp="$APP/Watch/RecompWatch.app"
  [ -d "$wapp" ] || return 0
  WUDID=$(watch_udid)
  xcrun simctl boot "$WUDID" 2>/dev/null || true
  xcrun simctl bootstatus "$WUDID" -b >/dev/null
  xcrun simctl install "$WUDID" "$wapp"
  xcrun simctl launch "$WUDID" "$BUNDLE.watchkitapp" >/dev/null || true
  echo "Recomp aperta anche sull'Apple Watch simulato."
}

run() {
  xcrun simctl boot "$UDID" 2>/dev/null || true
  open -a "$(xcode-select -p)/Applications/Simulator.app" # col percorso: da un collegamento remoto «open -a Simulator» non lo trova
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  echo "Recomp aperta nel simulatore."
  watch_run
}

# solo il sito: lo copio dentro il progetto già pronto (senza "cap copy", che riscriverebbe l'elenco dei plugin)
web() {
  local pub=ios/App/App/public
  rm -rf "$pub/assets"
  cp ../index.html ../manifest.webmanifest "$pub/"
  cp -R ../assets "$pub/"
}

UDID=$(pick)
case "${1:-}" in
  "")
    bash prepara.sh
    build && run ;;
  web)
    [ -d ios/App ] || { echo "Prima lancia app-ios/simulatore.sh senza parametri"; exit 1; }
    web && build && run ;;
  app)
    [ -d ios/App ] || { echo "Prima lancia app-ios/simulatore.sh senza parametri"; exit 1; }
    cp native/Shared/RestAttributes.swift native/App/*.swift ios/App/App/
    cp native/Shared/RestAttributes.swift native/RecompLive/* ios/App/RecompLive/
    if [ -d ios/App/RecompWatch ]; then # app Watch e complicazione
      cp -R native/Watch/App/. native/Watch/Shared/. ios/App/RecompWatch/
      cp -R native/Watch/Widgets/. native/Watch/Shared/. ios/App/RecompWatchWidgets/
      cp resources/icon-1024.png ios/App/RecompWatch/Assets.xcassets/AppIcon.appiconset/
    fi
    web && build && run ;;
  vai)
    url="recomp://${2:-oggi}"
    [ -n "${3:-}" ] && url="$url?tema=$3"
    # riavvio l'app con il link come argomento: «simctl openurl» farebbe comparire la richiesta di conferma di iOS
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -recompUrl "$url" >/dev/null
    echo "Aperto $url" ;;
  orologio-vai)
    WUDID=$(watch_udid)
    args=(-recompPage "${2:-oggi}")
    case "${3:-}" in "") ;; fine) args+=(-recompStop YES) ;; *) args+=(-recompStart "$3") ;; esac
    xcrun simctl launch --terminate-running-process "$WUDID" "$BUNDLE.watchkitapp" "${args[@]}" >/dev/null
    case "${3:-}" in "") echo "Orologio: pagina ${2:-oggi}" ;; fine) echo "Orologio: allenamento di prova chiuso" ;; *) echo "Orologio: scheda $3 avviata" ;; esac ;;
  foto|orologio)
    mkdir -p screenshots
    out="screenshots/${2:-$(date +%H%M%S)}.png"
    dev="$UDID"; [ "$1" = orologio ] && dev=$(watch_udid)
    xcrun simctl io "$dev" screenshot "$out" >/dev/null
    echo "app-ios/$out" ;;
  *)
    sed -n '2,11p' "$0"; exit 1 ;;
esac
