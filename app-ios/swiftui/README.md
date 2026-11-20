# Recomp: l'app iPhone in SwiftUI

L'app iPhone di Recomp, senza il sito dentro. Si costruisce e si installa da Windows con xtool (`app-ios/xtool/README.md`),
insieme all'app Apple Watch. Il sito web resta un visualizzatore (allenamenti e pasti da PC o tablet).

## Come si costruisce e si installa
- `powershell -ExecutionPolicy Bypass -File app-ios\xtool\windows\installa.ps1` installa iPhone e orologio (e rinnova la firma).
- `... installa.ps1 compila` controlla che compili (senza telefono); `... installa.ps1 orologio` rifà solo l'orologio.
- Identificativo `io.github.splancxs.recomp.prova`, nome «Recomp», gruppo `group.io.github.splancxs.recomp`, indirizzi `recomp://`.
- Profilo gratuito: al massimo 3 app installate insieme e 10 identificativi nuovi ogni 7 giorni.
- Dopo una dieta nuova: `python tools/genera_piano.py` e poi `python tools/piano_swift.py` (scrive `Resources/piano.json`).

## Com'è fatta (Sources/RecompNuova)
- `Piano.swift`, `Aiuti.swift`, `Cibi.swift`: il piano (da `Resources/piano.json`), i pezzi e le icone dei cibi.
- `Modelli.swift`, `Store.swift`, `Allenamento.swift`: i dati (file in Application Support) e la logica di pasti, pesi,
  schede, allenamento in corso, recupero, record, blocco di 7 settimane.
- `FuoriPiano.swift`, `CibiFuori.swift`, `Giornata.swift`: pasti cambiati o in più (cibi del piano, cibi comuni fuori casa,
  Open Food Facts, a mano), i miei pasti, «Sistema la giornata».
- `WatchBridge.swift`: WatchConnectivity con l'app Watch (`app-ios/native/Watch`).
- `Salute.swift`, `Promemoria.swift`, `Backup.swift`, `RiepilogoSettimana.swift`: Salute, notifiche, backup, la domenica.
- `Coach.swift`, `AzioniCoach.swift`, `CoachScrive.swift`: il coach (Gemini, Mistral o Claude), le azioni dalla chat e i
  messaggi che manda da solo; `RitmoPeso.swift`: il ritmo del peso con le regole del nutrizionista.
- Viste: `OggiView`, `PianoView`, `AllenamentoView`, `SchedaAttivaView`, `ProgressiView`, `ProfiloView`; stile in `Tema.swift`
  (grafite e argento tipo Lift, accento rosso).
- Live Activity e widget della Home: estensione `RecompLive` con i file di `app-ios/native/RecompLive` e `Home`.
