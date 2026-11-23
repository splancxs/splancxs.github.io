"""Giro di controllo di Recomp sull'iPhone vero, con UNA sola connessione per tutto il giro (debug.sh giro / stato).

Per ogni riga di giro.txt («nome|azioni|schermata|scorri») rilancia l'app in MODALITÀ PROVA (copia dei dati), aspetta il
suo «RECOMP pronto» (niente attese fisse), salva lo stato in testo (nome.txt: pasti, grammi, kcal, macro, scambi,
serie) e lo screenshot (nome.png, non con --testo). Gli errori dell'app («RECOMP ERRORE») si stampano subito.
Alla fine rilancia l'app normale (dati veri).

Uso (con il tunnel di «debug.sh prepara» attivo):
  giro.py <bundle> <cartella> <lista.txt> [--testo]
  giro.py <bundle> <cartella> --una "<azioni>" <schermata> [scorri] [--foto]     una sola prova, stato a schermo
"""
import asyncio
import sys
import time
from pathlib import Path

from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider
from pymobiledevice3.services.dvt.instruments.process_control import ProcessControl
from pymobiledevice3.services.dvt.instruments.screenshot import Screenshot
from pymobiledevice3.services.os_trace import OsTraceService
from pymobiledevice3.tunneld.api import get_tunneld_devices

messaggi: list[str] = []   # i messaggi «RECOMP …» dell'app, nell'ordine in cui arrivano
orari: list = []           # l'ora del telefono di ogni messaggio (per misurare i millisecondi)


INTENTI = ("Meno15RecuperoIntent", "Piu15RecuperoIntent", "SaltaRecuperoIntent", "SegnaSerieIsolaIntent")
PROCESSI = {"chronod", "linkd", "BackgroundShortcutRunner", "WidgetRenderer_Activities", "RecompLive", "RecompNuova",
            "SpringBoard", "liveactivitiesd"}
completo: list[str] = []   # prova dell'isola: tutti i messaggi di quei processi, salvati in isola-sistema.log
sistema = False   # prova dell'isola: anche i messaggi di iOS che nominano i pulsanti (per misurare tocco → app)


async def ascolta(rsd):
    async for voce in OsTraceService(rsd).syslog():
        i = voce.message.find("RECOMP ")
        if i >= 0:
            messaggi.append(voce.message[i + 7:])
            orari.append(voce.timestamp)
        elif sistema:
            processo = voce.filename.rsplit("/", 1)[-1]
            if processo in PROCESSI or any(x in voce.message for x in INTENTI):
                # tutto nel file (per capire dove aspetta iOS); a schermo solo tocco e fine dell'azione
                completo.append(f"{voce.timestamp.strftime('%H:%M:%S.%f')[:-3]} {processo}: {voce.message[:300]}")
                if "Handle action" in voce.message or "Successfully ran action" in voce.message or "Failed" in voce.message:
                    messaggi.append(f"sistema {processo}: {voce.message[:90]}")
                    orari.append(voce.timestamp)


async def prova(pc, foto, bundle, azioni, schermata, scorri, png):
    da = len(messaggi)
    t0 = time.monotonic()
    env = {"RECOMP_PROVA": "1", "RECOMP_AZIONI": azioni, "RECOMP_APRI": schermata or "oggi", "RECOMP_SCORRI": scorri}
    await pc.launch(bundle_id=bundle, kill_existing=True, environment=env)
    pronto = False
    while time.monotonic() - t0 < 20:
        if any(m.startswith("pronto") for m in messaggi[da:]):
            pronto = True
            break
        await asyncio.sleep(0.1)
    righe = messaggi[da:]
    if pronto and png is not None:
        await asyncio.sleep(0.35)   # l'ultima animazione (finestra o scorrimento)
        png.write_bytes(await foto.get_screenshot())
    return pronto, righe, time.monotonic() - t0


async def main():
    bundle, cartella = sys.argv[1], Path(sys.argv[2])
    resto = sys.argv[3:]
    cartella.mkdir(parents=True, exist_ok=True)
    rsds = await get_tunneld_devices()
    if not rsds:
        print("Nessun iPhone nel tunnel: lancia prima «debug.ps1 prepara».")
        return 1
    rsd = rsds[0]
    ascoltatore = asyncio.create_task(ascolta(rsd))
    await asyncio.sleep(1.0)   # il registro deve essere già aperto quando l'app parte
    errori = 0
    async with DvtProvider(rsd) as dvt, ProcessControl(dvt) as pc, Screenshot(dvt) as foto:
        if resto and resto[0] == "--isola":
            # prova della Dynamic Island: allenamento finto con l'isola accesa (RECOMP_LIVE), poi per N secondi si stampano
            # i tocchi sui pulsanti dell'isola con i millisecondi, dall'estensione e dall'app
            global sistema
            sistema = True
            secondi = int(resto[1]) if len(resto) > 1 and resto[1].isdigit() else 90
            env = {"RECOMP_PROVA": "1", "RECOMP_LIVE": "1", "RECOMP_AZIONI": "avvia:TA;serie:0:0", "RECOMP_APRI": "scheda"}
            da = len(messaggi)
            await pc.launch(bundle_id=bundle, kill_existing=True, environment=env)
            print(f"Allenamento di prova avviato, recupero in corso. Esci dall'app e tocca −15″, +15″, Salta sull'isola "
                  f"(tienila premuta). Ascolto per {secondi} s…", flush=True)
            t0 = time.monotonic()
            while time.monotonic() - t0 < secondi:
                while da < len(messaggi):
                    m = messaggi[da]
                    da += 1
                    if m.startswith(("isola", "ERRORE", "app ", "sistema")):
                        print(f"[{orari[da - 1].strftime('%H:%M:%S.%f')[:-3]}] {m}", flush=True)
                await asyncio.sleep(0.1)
            (cartella / "isola-sistema.log").write_text("\n".join(completo) + "\n", encoding="utf-8")
            print(f"Registro completo del sistema: {cartella / 'isola-sistema.log'} ({len(completo)} righe)")
            # fine prova: l'app normale chiude l'isola dell'allenamento finto (quello vero non esiste)
            await pc.launch(bundle_id=bundle, kill_existing=True, environment={"RECOMP_PROVA": "1", "RECOMP_LIVE": "1",
                                                                              "RECOMP_AZIONI": "annulla", "RECOMP_APRI": "oggi"})
            await asyncio.sleep(3)
        elif resto and resto[0] == "--una":
            azioni, schermata = resto[1], resto[2]
            scorri = next((x for x in resto[3:] if not x.startswith("--")), "")
            png = cartella / "stato.png" if "--foto" in resto else None
            pronto, righe, secondi = await prova(pc, foto, bundle, azioni, schermata, scorri, png)
            print("\n".join(righe))
            print(f"[{secondi:.1f} s]" + ("" if pronto else " NESSUNA RISPOSTA: l'app si è chiusa? (debug.ps1 crash)")
                  + (f" · screenshot {png}" if png and pronto else ""))
            errori = 0 if pronto else 1
        else:
            lista, testo = Path(resto[0]), "--testo" in resto
            inizio = time.monotonic()
            for vecchio in list(cartella.glob("*.png")) + list(cartella.glob("*.txt")) + list(cartella.glob("foglio_*.jpg")):
                vecchio.unlink()
            for riga in lista.read_text(encoding="utf-8").splitlines():
                riga = riga.strip()
                if not riga or riga.startswith("#"):
                    continue
                parti = (riga.split("|") + ["", "", "", ""])[:4]
                nome, azioni, schermata, scorri = (p.strip() for p in parti)
                png = None if testo else cartella / f"{nome}.png"
                pronto, righe, secondi = await prova(pc, foto, bundle, azioni, schermata, scorri, png)
                (cartella / f"{nome}.txt").write_text("\n".join(righe) + "\n", encoding="utf-8")
                sbagli = [r for r in righe if r.startswith("ERRORE")]
                if not pronto:
                    errori += 1
                    print(f"NESSUNA RISPOSTA  {nome}: l'app si è chiusa o non è partita (debug.ps1 crash)")
                else:
                    print(f"ok  {nome:<24} {secondi:4.1f} s" + (f"  · {len(sbagli)} errori dell'app" if sbagli else ""))
                for s in sbagli:
                    print("      " + s)
                errori += len(sbagli)
            print(f"Giro: {time.monotonic() - inizio:.0f} s, {errori} problemi. Stato e screenshot in {cartella}")
        # l'app torna normale, con i dati veri
        await pc.launch(bundle_id=bundle, kill_existing=True, environment={})
    ascoltatore.cancel()
    return 1 if errori else 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
