# Recomp dal PC Windows (senza Mac): iPhone e Apple Watch con xtool

Costruisce e installa l'app iPhone (SwiftUI, `app-ios/swiftui`) **e l'app Apple Watch** (`app-ios/native/Watch`) da Windows,
con un Apple ID gratuito, usando [xtool](https://github.com/xtool-org/xtool) dentro WSL (Linux). La firma gratuita dura
**7 giorni**: per rinnovarla basta rilanciare lo stesso comando.

## Rinnovare e aggiornare (ogni 7 giorni, o dopo una modifica)

1. Collega l'iPhone al PC **col cavo** e sbloccalo. Sblocca anche l'orologio e tienilo al polso.
2. Da PowerShell, nella cartella del repository:

```powershell
powershell -ExecutionPolicy Bypass -File app-ios\xtool\windows\installa.ps1
```

In ordine: copia sul PC i backup automatici dell'iPhone (`BACKUP_DIR` in `config.sh`), registra l'orologio sul team se
serve, prepara il progetto dentro Linux, compila l'app Watch **solo se il suo codice è cambiato**, compila l'app iPhone
(solo i file cambiati), la firma e la installa, poi installa l'app Watch **direttamente sull'orologio**. Se l'orologio
risponde «Coordinator found … process-scoped» (installazione di prima rimasta a metà) riprova da solo dopo 20 secondi.

| Comando | Cosa fa |
|---|---|
| `installa.ps1` | tutto: iPhone + orologio (anche il rinnovo della firma) |
| `installa.ps1 orologio` | solo l'installazione sull'orologio, con l'app già pronta dall'ultima volta |
| `installa.ps1 compila` | controlla che compili, senza telefono |

> **Ordine obbligato**: prima l'app iPhone, poi l'orologio. Reinstallare l'app iPhone fa ritenere all'iPhone che l'app
> Watch non sia installata finché non si reinstalla anche l'orologio: il comando fa sempre tutte e due.

**Serve il cavo.** In Wi-Fi l'installazione dell'iPhone si blocca e il servizio che porta all'orologio (`companion_proxy`)
chiude la connessione: lo script si ferma subito se vede l'iPhone solo in Wi-Fi.

**Rete di WSL «mirrored».** Con `C:\Users\<utente>\.wslconfig` contenente `[wsl2]` e `networkingMode=mirrored`, Linux
raggiunge il servizio Apple di Windows su `127.0.0.1:27015` senza altro. Se «Non raggiungo l'iPhone»: apri l'app
**Apple Devices** su Windows e collega e sblocca l'iPhone. Senza la rete mirrored serve `windows\porta.ps1` (amministratore).

Non esiste un simulatore dell'Apple Watch su Windows: si prova sull'orologio vero. Screenshot dell'orologio: app Watch
dell'iPhone → Generali → Abilita screenshot, poi tasto laterale + corona insieme (finiscono in Foto sull'iPhone).

## Che cosa c'è

| Cosa | Dove |
|---|---|
| Comando unico (Linux) e il suo lanciatore per Windows | `installa.sh`, `windows/installa.ps1` |
| Compilazione dell'app Watch e della complicazione | `costruisci-orologio.sh` |
| Installazione diretta sull'orologio | `orologio_installa.py` |
| Backup dell'iPhone copiati sul PC a ogni rinnovo | `copia_backup.py` |
| Abbinamento una tantum e Modalità sviluppatore dell'orologio | `orologio_sviluppatore.py` |
| Modifiche al codice di xtool (e la loro prova) | `patches/`, `prova-patch.sh` |
| Preparazione una tantum di Linux | `prepara-wsl.sh` (una ricetta, da leggere) |
| Porta per Windows senza rete mirrored | `windows/porta.ps1` |
| Configurazione locale (UDID dell'orologio, cartella dei backup) | `config.sh` (da `config.esempio.sh`; **non va su GitHub**) |

I file Swift non sono duplicati: l'app iPhone viene da `app-ios/swiftui`, Live Activity, widget e modelli condivisi da
`app-ios/native/`. Identificativo: `io.github.splancxs.recomp.prova` (con l'Apple ID gratuito xtool aggiunge `XTL-…`).

## Perché serve tutto questo (problemi incontrati e come sono risolti)

| Problema | Causa | Soluzione |
|---|---|---|
| La barra in basso non ha il Liquid Glass | il linker di xtool marca il programma «sdk 17.0» e iOS lo tratta da app vecchia | `-platform_version ios 18.0 27.0` nei `linkerSettings` |
| La Live Activity non c'è: estensione «vuota» (49 KB) | il codice sta in un archivio `.a` e il linker prende solo i pezzi richiesti: `main` non lo è | `-u _main` nei `linkerSettings` dell'estensione |
| «Can't find free space of LoadCommands for CodeSignature» | poco spazio nell'intestazione del file | `-headerpad 0x4000` |
| xtool vuole revocare un certificato | l'Apple ID aveva già il certificato di AltStore | usare un Apple ID nuovo e vuoto per xtool |
| Limite «3 app» | per l'iPhone contano tutte le app firmate con profilo gratuito, di qualsiasi Apple ID | tenere liberi i posti |
| xtool non fa app Watch | l'SDK scarta watchOS, nessun supporto alle app annidate | `patches/applica-patch.py` + SDK ricostruito con watchOS |
| Il compilatore non trova watchOS / `.tbd` malformati | lld 21 non conosce `arm64e.x1-watchos` | `patches/correggi-tbd-watchos.py` |
| L'app Watch non compare nell'app Watch dell'iPhone | il Watch SE 3 è a **64 bit (arm64)**; avevo compilato per arm64_32 | compilare per `arm64-apple-watchos` |
| «Non è stato trovato un profilo valido» | il profilo elencava solo l'iPhone (xtool scarta gli Apple Watch) e la firma usava i permessi dell'app principale per tutto | patch ai profili e alla firma (zsign: una risorsa di firma per ogni parte) |
| «Authorized by a free provisioning profile, but … not allowed to be installed from this source» | l'orologio rifiuta i profili gratuiti che arrivano dal tasto «Installa» dell'iPhone | installazione **diretta** con `com.apple.streaming_zip_conduit`, come fa Xcode (`orologio_installa.py`) |
| L'orologio non si vede dal PC | Xcode usa Bluetooth e Wi-Fi diretto Apple, che qui mancano | si passa **attraverso l'iPhone**: `companion_proxy` inoltra ogni porta dell'orologio |
| Nessun interruttore «Modalità sviluppatore» sull'orologio | compare solo dopo la richiesta AMFI «reveal» | `orologio_sviluppatore.py reveal`, poi attivarla a mano |
| L'orologio resta su «Apri Recomp sull'iPhone» | dopo aver reinstallato l'app iPhone, `appInstalled` torna NO | reinstallare l'orologio subito dopo |

L'installazione dell'iPhone passa dal servizio Apple di Windows (app «Apple Devices», porta 27015) e **non** da usbipd,
che dà `opTimeout` durante il trasferimento dei file.

## Limiti noti

- Firma gratuita: 7 giorni, massimo 3 app sull'iPhone, 10 identificativi nuovi ogni 7 giorni.
- La **complicazione** sul quadrante può non avere dati: xtool rinomina il gruppo condiviso e `WatchShared` usa il nome fisso.
- xtool è fissato al commit `d802c71`: con un xtool più nuovo le modifiche potrebbero non applicarsi (il controllo lo dice).
- L'icona dell'app Watch è un PNG sciolto (xtool non ha il compilatore dei cataloghi di Apple).
