# Recomp · piano personale

Sito statico (GitHub Pages) con piano alimentare calcolato al grammo, scheda Torso/Limbs con diario dei carichi, lista della spesa e monitoraggio del peso. Nessun framework, nessuna build: HTML, CSS e JavaScript.

Illustrazioni degli esercizi in `assets/esercizi/`: [Everkinetic](https://github.com/everkinetic/data), licenza CC BY-SA 4.0.

## Struttura

| Percorso | Contenuto |
|---|---|
| `index.html` | Pagina unica (sezioni: Oggi, Piano, Scheda, Progressi, Guida) |
| `assets/js/data.js` | **Generato**: alimenti, ricette, grammature, settimana tipo, scheda |
| `assets/js/app.js` | Logica del sito (calcoli, scambi, timer, progressi, grafico) |
| `assets/js/allenamento.js` | Allenamento stile Hevy: routine modificabili, allenamento live con "Precedente", recupero automatico, cronologia, record e statistiche |
| `assets/css/style.css` | Stile (tema chiaro/scuro, mobile first) |
| `tools/genera_piano.py` | Database alimenti, ricette, target, ottimizzazione e verifica |
| `tools/genera_icone.py` | Genera le icone PNG |
| `sw.js`, `manifest.webmanifest` | Uso offline e installazione su telefono |

## Installarlo come app su iPhone

1. Apri `https://splancxs.github.io` con **Safari** (non Chrome: su iPhone solo Safari installa le web app).
2. Tocca **Condividi** → **Aggiungi alla schermata Home** → **Aggiungi**.
3. Da quel momento usa sempre l'icona Recomp: si apre a schermo intero, funziona offline e tiene i tuoi dati (pesi, carichi, spunte).

I dati dell'app installata sono separati da quelli di Safari: per spostarli usa Progressi → Esporta / Importa backup. Il timer di recupero suona solo se l'iPhone non è in modalità silenziosa; in ogni caso la barra del timer diventa lime allo scadere.

## App iPhone nativa (Capacitor)

`app-ios/` contiene il guscio nativo: il sito viene copiato dentro l'app (funziona offline) e in più ci sono notifiche locali (promemoria, fine recupero) e vibrazione. Apple Salute non è inclusa: con un Apple ID gratuito né AltStore né Sideloadly mantengono il permesso HealthKit (verificato anche con un'app nativa di prova); servirebbe l'Apple Developer Program. Le funzioni native si attivano solo dentro l'app (`window.Capacitor`), sul sito restano spente.

- Compilazione: `.github/workflows/app-iphone.yml` gira su un Mac di GitHub a ogni modifica di sito o `app-ios/` e pubblica una **Release** con `Recomp.ipa` e `altstore-source.json`. Le note della Release riportano gli entitlement incorporati.
- Installazione: **AltStore** con il proprio Apple ID gratuito, aggiungendo la sorgente `https://github.com/splancxs/splancxs.github.io/releases/latest/download/altstore-source.json`. Con l'Apple ID gratuito l'app va rinnovata ogni 7 giorni (AltStore lo fa da solo se AltServer è acceso sul PC).
- `app-ios/patch-ios.mjs` adatta il progetto generato (solo verticale, icona e splash da `app-ios/resources/`).

## Sincronizzazione PC ↔ telefono (Firebase)

`assets/js/sync.js` salva tutti i dati dell'app in Firestore (documento `users/{uid}`) e li tiene allineati tra i dispositivi. Si attiva quando `assets/js/firebase-config.js` contiene la configurazione del progetto.

Regole di Firestore (console Firebase → Firestore Database → Regole):

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{uid} {
      allow read, write: if request.auth != null && request.auth.uid == uid;
    }
  }
}
```

Dopo aver creato il proprio account dall'app, conviene disattivare la creazione di nuovi account: Authentication → Impostazioni → Azioni utente → togliere "Abilita creazione (registrazione)".

## Modificare il piano

1. Cambia valori, ricette o target in `tools/genera_piano.py`.
2. Esegui `python tools/genera_piano.py`: ricalcola le grammature, stampa il report di verifica e riscrive `assets/js/data.js`.
3. Aumenta il numero di versione `?v=` in `index.html` e `sw.js` (e il nome `CACHE` in `sw.js`), così telefoni e browser scaricano i file nuovi.

## Come sono calcolati i numeri

- Valori per 100 g da tabelle CREA, USDA ed etichette dei prodotti (la fonte è indicata per ogni alimento nella sezione Guida → Alimenti).
- Riga: kcal arrotondate all'intero, macro a 0,1 g. Totale del pasto = somma delle righe. Totale del giorno = somma dei pasti. Il sito e lo script usano lo stesso identico arrotondamento, quindi i numeri coincidono.
- I dati personali (pesi, carichi, spunte) restano solo nel browser (`localStorage`): non vengono pubblicati.
