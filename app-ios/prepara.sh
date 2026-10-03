#!/bin/bash
# Crea da zero il progetto Xcode dell'app iPhone (cartella app-ios/ios) a partire dal sito del repository.
# Lo usano sia GitHub Actions (.github/workflows/app-iphone.yml) sia simulatore.sh sul Mac: i passi sono gli stessi.
# Gira su macOS, dalla cartella app-ios. Con WATCH=1 (simulatore.sh e installazione da Xcode) aggiunge anche l'app Watch.
set -euo pipefail
cd "$(dirname "$0")"

npm install --no-audit --no-fund
rm -rf www ios
mkdir -p www
cp ../index.html ../manifest.webmanifest www/
cp -R ../assets www/
npx cap add ios
node patch-ios.mjs
# Live Activity del recupero e barra in basso nativa: file nativi dell'app ed estensione RecompLive
cp native/Shared/RestAttributes.swift native/App/*.swift ios/App/App/
mkdir -p ios/App/RecompLive
cp native/Shared/RestAttributes.swift native/RecompLive/* ios/App/RecompLive/
if ! ruby -e "require 'xcodeproj'" 2>/dev/null; then
  if [ -n "${CI:-}" ]; then
    sudo gem install xcodeproj --no-document
  else
    # Ruby di sistema del Mac (2.6): xcodeproj 1.28+ e CFPropertyList 3.0.7+ vogliono «nkf», che con Xcode 26 non si compila.
    # Installo a mano versioni che funzionano, una per una.
    for g in CFPropertyList:3.0.6 atomos:0.1.3 colored2:3.1.2 claide:1.1.0 nanaimo:0.4.0 rexml:3.4.4 xcodeproj:1.27.0; do
      gem install --user-install --no-document --ignore-dependencies "${g%%:*}" -v "${g##*:}"
    done
  fi
fi
npx cap sync ios
# dopo "cap sync": Capacitor copia nel suo Package.swift la versione iOS più alta del progetto,
# e l'iOS 18 dell'estensione (serve per l'Apple Watch) non è accettato dal suo formato
ruby add-live-activity.rb
# app per Apple Watch e complicazione: solo nelle compilazioni da Xcode sul Mac
if [ -n "${WATCH:-}" ]; then
  mkdir -p ios/App/RecompWatch ios/App/RecompWatchWidgets
  cp -R native/Watch/App/. native/Watch/Shared/. ios/App/RecompWatch/
  cp -R native/Watch/Widgets/. native/Watch/Shared/. ios/App/RecompWatchWidgets/
  cp resources/icon-1024.png ios/App/RecompWatch/Assets.xcassets/AppIcon.appiconset/
  # Salute sull'iPhone: permesso HealthKit e testi della richiesta di accesso (AltStore toglierebbe il permesso)
  cp native/App/App.entitlements ios/App/App/
  plutil -replace RecompHealth -bool YES ios/App/App/Info.plist
  plutil -replace NSHealthShareUsageDescription -string "Recomp legge le pesate, i passi e le calorie attive per il tuo percorso." ios/App/App/Info.plist
  plutil -replace NSHealthUpdateUsageDescription -string "Recomp salva in Salute le pesate e i pasti che segni." ios/App/App/Info.plist
  ruby add-watch.rb
fi
# i plugin di Recomp (RestActivity, NativeTabs, WatchBridge, Health) vanno nell'elenco che Capacitor legge all'avvio (come notifiche e vibrazione):
# così l'app li trova in window.Capacitor.Plugins. "cap sync" riscrive il file, quindi si aggiungono dopo.
node -e "const fs=require('fs'),f='ios/App/App/capacitor.config.json',c=JSON.parse(fs.readFileSync(f,'utf8'));c.packageClassList=[...new Set([...(c.packageClassList||[]),'RestActivityPlugin','NativeTabsPlugin','WatchBridgePlugin','HealthPlugin'])];fs.writeFileSync(f,JSON.stringify(c,null,2));console.log('Plugin registrati:',c.packageClassList.join(', '))"
