# Recomp: note di lavoro

App personale di dieta e allenamento. L'app vera è quella **iPhone in SwiftUI** (`app-ios/swiftui`) con la sua **app Apple
Watch** (`app-ios/native/Watch`), installate dal PC Windows con xtool e un Apple ID gratuito. Il sito statico (GitHub Pages,
https://splancxs.github.io) resta come visualizzatore da PC o tablet.

## Come lavorare
- L'utente è italiano: rispondi in italiano, in modo semplice e diretto. Commenti nel codice in italiano.
- Prima di modifiche grandi (nuove funzioni, dieta, grafica di intere pagine) proponi un piano o delle opzioni e aspetta l'ok.
- Si lavora da due computer (PC Windows e Mac): prima di iniziare `git pull`, e un computer alla volta.
- Mai chiavi API, password o dati personali nel repository: è pubblico.

## File
- App iPhone: `app-ios/swiftui` (spiegata in `app-ios/swiftui/README.md`). Live Activity, widget della Home e modelli
  condivisi con l'orologio: `app-ios/native/RecompLive`, `Home`, `Shared`, `Watch/Shared`.
- Sito, solo da consultare (Dieta e Scheda, niente registrazioni): `index.html`, `assets/css/style.css`, `assets/js/app.js`,
  `assets/js/data.js` (generato: non modificarlo a mano), `sw.js`. Nel browser solo comodità (`rc.web.*`, `rc.theme`).
- `tools/genera_piano.py` rigenera `assets/js/data.js` (piano alimentare e schede) e verifica i conti; `tools/piano_swift.py`
  ne ricava `app-ios/swiftui/Resources/piano.json` per l'app. La dieta arriva dal nutrizionista (`tools/dieta.json`).

## Regole di grafica e di contenuto
- Lime (`#c4f031`) solo come riempimento con testo scuro sopra; mai testo lime su fondo chiaro (sul chiaro si usa il verde oliva `#4d6b00`).
- Stile sportivo: titoli in carattere condensato maiuscolo; deve stare bene su iPhone (390 px di larghezza) e su PC, in tema chiaro e scuro.
- Porzioni da piatto vero (panino con 2 fette, niente 30 g di riso): i conti si adattano alle porzioni, non il contrario. L'utente pesa il cibo: grammi prima di tutto.

## Installare dal PC Windows (xtool, senza Mac)
- Tutto è spiegato in `app-ios/xtool/README.md`. Un solo comando, anche per rinnovare la firma ogni 7 giorni
  (iPhone collegato **col cavo** e sbloccato, orologio sbloccato e al polso):
  `powershell -ExecutionPolicy Bypass -File app-ios\xtool\windows\installa.ps1`
  - `installa.ps1 compila`: controlla che compili, senza telefono.
  - `installa.ps1 orologio`: rifà solo l'installazione sull'orologio.
- Ricompila solo quello che è cambiato (l'app Watch solo se cambia il suo codice) e riprova da solo l'errore «Coordinator» dell'orologio.
- Ordine obbligato: prima l'app iPhone, poi l'app Watch installata direttamente sull'orologio (il comando lo fa già).
- Identificativo `io.github.splancxs.recomp.prova` (nome «Recomp»). Profilo gratuito: 3 app e 10 identificativi nuovi ogni 7 giorni.
- `app-ios/xtool/config.sh` (UDID dell'orologio, cartella dei backup) non va mai su GitHub.

## Pubblicare il sito
1. Se cambiano `index.html` o `assets/`: `python tools/versione.py` (alza `?v=` e la cache del service worker).
2. Commit e `git push` su `main`: il sito si aggiorna da solo.

## App Apple Watch (`app-ios/native/Watch`)
- Pagina «Oggi» (anello kcal, macro, prossimo pasto, creatina, Pasti, allenamento), Pasti con dettaglio (ingredienti e grammi,
  Annulla, Cambia piatto, I miei pasti), allenamento a due pagine (serie e riepilogo con «Termina»). I dati arrivano dall'iPhone
  (`WatchBridge.swift`).
- Allenamento avviato dal polso o dal telefono: l'altro lo specchia in diretta; se finisce o si annulla da una parte, si chiude
  anche dall'altra. Kg e ripetizioni si scelgono con le rotelle (corona).

## Cosa NON rifare
- Il 2026-10-18 l'utente ha scartato più redesign (brutalista, «Pulito», «Nuovo», menu a 4 voci, pagine a etichette e sezioni
  richiudibili) e ha chiesto di tornare all'interfaccia di prima tenendo solo i bug sistemati (sincronizzazione esatta
  iPhone↔orologio, annulla/fine allenamento, Live Activity che apre l'esercizio in corso). Non proporre redesign senza richiesta esplicita.
- La vecchia app iPhone con il sito dentro (Capacitor, AltStore, workflow di GitHub) è stata tolta il 2026-10-25: non rimetterla.
- «Palestra automatica» (posizione della palestra) tolta il 2026-10-25: l'utente non la vuole per la batteria.
