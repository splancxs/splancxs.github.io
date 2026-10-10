# Recomp dal PC Windows (senza Mac): iPhone e Apple Watch con xtool

Costruisce e installa l'app iPhone **e l'app Apple Watch** da Windows, con un Apple ID gratuito, usando
[xtool](https://github.com/xtool-org/xtool) dentro WSL (Linux). La firma gratuita dura **7 giorni**: per rinnovarla basta
rilanciare un comando.

L'altra strada (Xcode sul Mac, `app-ios/installa.sh`) resta valida: qui non la sostituisco, la affianco.

## Rinnovare (ogni 7 giorni)

1. Collega l'iPhone al PC col cavo e **sbloccalo**. Sblocca anche l'orologio e tienilo al polso.
2. Da PowerShell, nella cartella del repository:

```powershell
powershell -ExecutionPolicy Bypass -File app-ios\xtool\windows\installa.ps1
```

Fa, in ordine: prepara il progetto dal sito del repository e dai file nativi, compila l'app Watch, compila e firma
l'app iPhone (con dentro l'app Watch) e la installa, poi installa l'app Watch **direttamente sull'orologio**.
`installa.ps1 iphone` fa solo l'iPhone, `installa.ps1 orologio` solo l'orologio.
Dopo aver cambiato il codice dell'app Watch (`app-ios/native/Watch/`): `installa.ps1 watch` ricompila solo l'orologio e
rifà le due installazioni, senza ricompilare il sito e i plugin. Non esiste un simulatore dell'Apple Watch su Windows
(è una parte di macOS): si prova sull'orologio vero. Per avere gli screenshot dell'orologio: app Watch dell'iPhone →
Generali → Abilita screenshot; poi tasto laterale + corona insieme; le immagini finiscono in Foto sull'iPhone.

> **Ordine obbligato**: prima l'app iPhone, poi l'orologio. Reinstallare l'app iPhone fa ritenere all'iPhone che l'app
> Watch non sia installata (`WCSession: appInstalled NO`, e l'orologio resta su «Apri Recomp sull'iPhone») finché non
> si reinstalla l'orologio. Il comando lo fa già nell'ordine giusto.

**Senza cavo?** L'iPhone si installa anche via Wi-Fi (serve spegnere «Indirizzo Wi-Fi privato» per la rete di casa, così
il servizio Apple di Windows lo riconosce, e tenerlo sveglio e sbloccato), ma il servizio che porta all'**orologio**
(`companion_proxy`) chiude la connessione se l'iPhone è collegato via Wi-Fi: per l'orologio serve il cavo USB.
Provato il 10/10/2026: `installa.ps1 watch` senza cavo installa l'iPhone ma si ferma all'orologio.

Se «Non raggiungo l'iPhone»: apri l'app **Apple Devices** su Windows, collega e sblocca l'iPhone e, se hai riavviato il
PC, lancia `windows\porta.ps1` (chiede il permesso di amministratore).

## Che cosa c'è

| Cosa | Dove |
|---|---|
| Comando unico (Linux) | `installa.sh` |
| Compilazione dell'app Watch e della complicazione | `costruisci-orologio.sh` |
| Installazione diretta sull'orologio | `orologio_installa.py` |
| Abbinamento una tantum e Modalità sviluppatore | `orologio_sviluppatore.py` |
| Progetto xtool (Package, Info.plist, permessi, guscio SwiftUI) | `progetto/` |
| Modifiche al codice di xtool | `patches/` |
| Preparazione una tantum di Linux | `prepara-wsl.sh` (una ricetta, da leggere) |
| Wrapper e porta per Windows | `windows/` |
| Configurazione locale (UDID dell'orologio) | `config.sh` (da `config.esempio.sh`; **non va su GitHub**) |

I file Swift dell'app non sono duplicati: vengono presi da `app-ios/native/` e il sito da `index.html` e `assets/`.
Identificativo dell'app: `io.github.splancxs.recomp.prova` (con Apple ID gratuito xtool aggiunge il suo prefisso `XTL-…`).

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
