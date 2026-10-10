# Copia questo file in «config.sh» (nella stessa cartella) e correggi i valori.
# config.sh resta solo sul tuo computer: contiene l'identificativo del tuo orologio e non va su GitHub.

# Identificativo (UDID) dell'orologio. Si legge con:  python orologio_sviluppatore.py info
export WATCH_UDID="00008310-XXXXXXXXXXXXXXXX"
export WATCH_NOME="Apple Watch"

# cartella di lavoro dove si costruiscono le app (dentro Linux/WSL)
export LAVORO=/root/recomp-xtool

# codice di xtool con le nostre modifiche (vedi patches/) e il suo programma compilato
export XTOOL_SRC=/root/xtool-src
export XTOOL_PATCHATO="$XTOOL_SRC/.build/release/xtool"
# xtool normale (serve solo per compilare l'app iPhone)
export XTOOL_STD=xtool

# SDK costruito con xtool patchato: contiene anche watchOS (vedi README)
export SDK_OROLOGIO=/root/darwin-watch/darwin.xtoolsdk

# plugin ufficiali di Capacitor scaricati con npm (npm install nella cartella app-ios)
export NPM_CAP=/root/recomp-npm/node_modules/@capacitor

# Python con pymobiledevice3 (parla con l'orologio attraverso l'iPhone)
export PMD=/root/pmd/bin/python
