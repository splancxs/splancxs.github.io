#!/bin/bash
# Recomp nel simulatore iPhone di Xcode (solo su Mac, serve Xcode 26 per il Liquid Glass). Dalla cartella del repository:
#   app-ios/simulatore.sh                prepara il progetto, compila e apre l'app (la prima volta qualche minuto)
#   app-ios/simulatore.sh web            dopo una modifica a index.html o assets/: ricopia il sito, ricompila e riapre (meno di un minuto)
#   app-ios/simulatore.sh app            dopo una modifica ai file Swift in app-ios/native: ricompila e riapre
#   app-ios/simulatore.sh vai piano      apre una sezione (oggi, piano, scheda, progressi, profilo, coach)
#   app-ios/simulatore.sh vai piano chiaro   la stessa con il tema chiaro (chiaro, scuro, auto)
#   app-ios/simulatore.sh foto [nome]    screenshot del simulatore in app-ios/screenshots/
# Modello: SIM="iPhone 17 Pro" app-ios/simulatore.sh   (di base quello già acceso, se no l'iPhone Pro più recente)
set -euo pipefail
cd "$(dirname "$0")"
BUNDLE=io.github.splancxs.recomp
APP=build/Build/Products/Debug-iphonesimulator/App.app

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
  xcodebuild $target -scheme App -configuration Debug -sdk iphonesimulator -destination "id=$UDID" \
    -derivedDataPath build CODE_SIGNING_ALLOWED=NO -quiet build
}

run() {
  xcrun simctl boot "$UDID" 2>/dev/null || true
  open -a Simulator
  xcrun simctl bootstatus "$UDID" -b >/dev/null
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
  xcrun simctl install "$UDID" "$APP"
  xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
  echo "Recomp aperta nel simulatore."
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
    web && build && run ;;
  vai)
    url="recomp://${2:-oggi}"
    [ -n "${3:-}" ] && url="$url?tema=$3"
    xcrun simctl openurl "$UDID" "$url"
    echo "Aperto $url" ;;
  foto)
    mkdir -p screenshots
    out="screenshots/${2:-$(date +%H%M%S)}.png"
    xcrun simctl io "$UDID" screenshot "$out" >/dev/null
    echo "app-ios/$out" ;;
  *)
    sed -n '2,9p' "$0"; exit 1 ;;
esac
