# Recomp: note di lavoro

App personale di dieta e allenamento: un sito statico (GitHub Pages, https://splancxs.github.io) che è anche un'app iPhone
(Capacitor, cartella `app-ios/`, installata con AltStore e un Apple ID gratuito).

## Come lavorare
- L'utente è italiano: rispondi in italiano, in modo semplice e diretto. Commenti nel codice in italiano.
- Prima di modifiche grandi (nuove funzioni, dieta, grafica di intere pagine) proponi un piano o delle opzioni e aspetta l'ok.
- Si lavora da due computer (PC Windows e Mac): prima di iniziare `git pull`, e un computer alla volta.
- Mai chiavi API, password o dati personali nel repository: è pubblico.

## File
- `index.html`, `assets/css/style.css`, `assets/js/`: `app.js` (pagine, timer, piano, Profilo), `allenamento.js` (Scheda),
  `coach.js` (Coach e AI), `sync.js` (Firebase), `data.js` (generato: non modificarlo a mano).
- `tools/genera_piano.py` rigenera `assets/js/data.js` (piano alimentare e schede) e verifica i conti.
- Dati dell'utente in `localStorage` con chiavi `rc.*`; `sync.js` le unisce tra dispositivi (le chiavi in `SKIP` restano sul dispositivo).

## Regole di grafica e di contenuto
- Lime (`#c4f031`) solo come riempimento con testo scuro sopra; mai testo lime su fondo chiaro (sul chiaro si usa il verde oliva `#4d6b00`).
- Stile sportivo: titoli in carattere condensato maiuscolo; deve stare bene su iPhone (390 px di larghezza) e su PC, in tema chiaro e scuro.
- Porzioni da piatto vero (panino con 2 fette, niente 30 g di riso): i conti si adattano alle porzioni, non il contrario. L'utente pesa il cibo: grammi prima di tutto.

## Pubblicare
1. Se cambiano `index.html` o `assets/`: `python tools/versione.py` (alza `?v=` e la cache del service worker).
2. Commit e `git push` su `main`: il sito si aggiorna da solo; il workflow «App iPhone» compila l'app e la pubblica
   per AltStore (release `build-N`). Sul telefono l'app si aggiorna da AltStore → My Apps.
3. Se la compilazione fallisce, il workflow pubblica la release `build-log` con gli errori.

## Simulatore iPhone (solo Mac, Xcode 26)
- `app-ios/simulatore.sh`: prepara il progetto, compila e apre l'app nel simulatore (la prima volta qualche minuto).
- `app-ios/simulatore.sh web`: dopo una modifica a HTML/CSS/JS ricopia il sito e riapre l'app.
- `app-ios/simulatore.sh app`: dopo una modifica ai file Swift in `app-ios/native`.
- `app-ios/simulatore.sh vai piano chiaro`: apre una sezione (oggi, piano, scheda, progressi, profilo, coach), facoltativo il tema.
- `app-ios/simulatore.sh foto nome`: screenshot in `app-ios/screenshots/nome.png`; aprilo per guardare il risultato.
- Per provare il sito senza l'app: `python3 -m http.server 8765` nella cartella del repository.

## Parte nativa (`app-ios/`)
- `prepara.sh` crea il progetto Xcode (lo usano sia il workflow sia `simulatore.sh`); `patch-ios.mjs` sistema Info.plist, icone e link `recomp://`.
- Plugin di Recomp in `native/App`: `RestActivityPlugin` (Live Activity del recupero) e `NativeTabsPlugin` (barra in basso
  nativa con il Liquid Glass di iOS 26). Vanno registrati in `packageClassList` (lo fa `prepara.sh`).
- Estensione `native/RecompLive` (Live Activity su schermata di blocco, Dynamic Island e Apple Watch): da iOS 18;
  `add-live-activity.rb` la aggiunge al progetto e deve girare dopo `npx cap sync`.
- Firma gratuita (Apple ID senza abbonamento): HealthKit funziona, ma solo installando da Xcode (AltStore lo toglie);
  push notification e Siri invece richiedono l'account sviluppatore a pagamento.
