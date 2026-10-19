# Recomp 2: l'app iPhone in SwiftUI

Riscrittura dell'app iPhone senza Capacitor e senza il sito dentro. Si costruisce da Windows con xtool, come l'altra
(`app-ios/xtool/README.md`). Il sito resta com'è e diventerà solo un visualizzatore (allenamenti e pasti da PC o tablet).

## Come si costruisce e si installa
- `powershell -ExecutionPolicy Bypass -File app-ios\xtool\windows\installa-nuova.ps1 compila` controlla che compili (senza telefono).
- `... installa-nuova.ps1` installa «Recomp 2» (identificativo `io.github.splancxs.recomp.nuova`) e la sua app Watch, accanto all'app vecchia.
- `... installa-nuova.ps1 watch` ricompila solo l'orologio (come `installa.ps1 watch`: «orologio» reinstalla senza ricompilare).
- `... installa-nuova.ps1 tutto sostituisci` mette la nuova app **al posto** di «Recomp» (stesso identificativo, stessa app Watch).
  Prima esporta il backup dall'app vecchia (Profilo → Esporta backup) e dopo importalo qui (Profilo → Importa backup).
- **Limite del profilo gratuito: 3 app installate insieme** (oggi YouTube, AltStore e Recomp). Per averne una quarta bisogna toglierne una.
- Dopo ogni modifica a `piano.json`/schede: `python tools/genera_piano.py` e poi `python tools/piano_swift.py`.

## Com'è fatta (Sources/RecompNuova)
- `Piano.swift`, `Aiuti.swift`: dati del piano (da `Resources/piano.json`) e calcolo dei pasti, gli stessi numeri dell'app web.
- `Modelli.swift`, `Store.swift`, `Allenamento.swift`: i dati dell'utente (file in Application Support) e la logica: pasti, pesi,
  schede, allenamento in corso, recupero, record, blocco di 7 settimane.
- `WatchBridge.swift`: WatchConnectivity. Stesso protocollo dell'app web, quindi l'app Watch (`app-ios/native/Watch`) non cambia.
  Avvio dal telefono → `HKHealthStore.startWatchApp` apre l'orologio anche se chiuso; avvio dal polso → notifica sul telefono.
- `Salute.swift`, `Promemoria.swift`, `Backup.swift`: Salute, notifiche, esporta/importa (legge anche il backup dell'app web).
- Viste: `OggiView`, `PianoView`, `AllenamentoView`, `SchedaAttivaView`, `ProgressiView`, `ProfiloView`; stile in `Tema.swift`
  (grafite e argento tipo Lift, accento rosso, barra in basso a sole icone).
- Live Activity e widget: stessa estensione dell'app vecchia (`app-ios/native/RecompLive`, `Home`); riaprono l'app con `recomp2://`.

## Ancora da fare
Coach AI (chat), sincronizzazione tra dispositivi (Firebase), pasto fuori piano, foto prima/dopo, CSV, widget della Home verificato,
modifica delle schede, grafici per esercizio. Mai provata su schermo: la prima installazione serve a trovare i difetti di aspetto.
