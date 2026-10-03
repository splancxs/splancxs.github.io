#!/bin/bash
# Crea da zero il progetto Xcode dell'app iPhone (cartella app-ios/ios) a partire dal sito del repository.
# Lo usano sia GitHub Actions (.github/workflows/app-iphone.yml) sia simulatore.sh sul Mac: i passi sono gli stessi.
# Gira su macOS, dalla cartella app-ios.
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
  if [ -n "${CI:-}" ]; then sudo gem install xcodeproj --no-document; else gem install --user-install xcodeproj --no-document; fi
fi
npx cap sync ios
# dopo "cap sync": Capacitor copia nel suo Package.swift la versione iOS più alta del progetto,
# e l'iOS 18 dell'estensione (serve per l'Apple Watch) non è accettato dal suo formato
ruby add-live-activity.rb
# i plugin di Recomp (RestActivity, NativeTabs) vanno nell'elenco che Capacitor legge all'avvio (come notifiche e vibrazione):
# così l'app li trova in window.Capacitor.Plugins. "cap sync" riscrive il file, quindi si aggiungono dopo.
node -e "const fs=require('fs'),f='ios/App/App/capacitor.config.json',c=JSON.parse(fs.readFileSync(f,'utf8'));c.packageClassList=[...new Set([...(c.packageClassList||[]),'RestActivityPlugin','NativeTabsPlugin'])];fs.writeFileSync(f,JSON.stringify(c,null,2));console.log('Plugin registrati:',c.packageClassList.join(', '))"
