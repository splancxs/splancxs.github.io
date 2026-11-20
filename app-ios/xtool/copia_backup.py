#!/usr/bin/env python3
"""Copia sul PC i backup automatici di Recomp: l'app ne salva uno al giorno in Documenti/Backup (si vedono anche nell'app
File dell'iPhone: Sul mio iPhone → Recomp → Backup). Lo lancia installa.sh a ogni rinnovo, prima di installare,
se in config.sh c'è BACKUP_DIR (una cartella di Windows vista da WSL, per esempio /mnt/c/Users/<nome>/Documents/Recomp backup).
Così i dati restano al sicuro anche se l'app sull'iPhone si cancella.

Uso: USBMUXD_SOCKET_ADDRESS=127.0.0.1:27015 python copia_backup.py <identificativo dell'app> <cartella>
L'identificativo è quello del progetto (io.github.splancxs.recomp.prova): il prefisso «XTL-…» di xtool lo trovo da solo."""
import asyncio
import os
import sys

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.services.house_arrest import HouseArrestService
from pymobiledevice3.services.installation_proxy import InstallationProxyService


async def main(identificativo: str, cartella: str) -> None:
    lockdown = await create_using_usbmux()
    app = await InstallationProxyService(lockdown=lockdown).get_apps(application_type="User")
    trovati = [b for b in app if b == identificativo or b.endswith("." + identificativo)]
    if not trovati:
        print("Backup: Recomp non è ancora sull'iPhone, niente da copiare.")
        return
    os.makedirs(cartella, exist_ok=True)
    # di solito basta la cartella Documenti (l'app la condivide con «UIFileSharingEnabled»); se non la vende, provo
    # l'intero contenitore, che le app firmate per sviluppo permettono di leggere
    try:
        casa = await HouseArrestService.create(lockdown, trovati[0], documents_only=True)
    except Exception:
        casa = await HouseArrestService.create(lockdown, trovati[0], documents_only=False)
    async with casa:
        try:
            nomi = await casa.listdir("/Documents/Backup")
        except Exception:
            print("Backup: sull'iPhone non ce n'è ancora nessuno (si crea aprendo l'app).")
            return
        copiati = 0
        for nome in sorted(nomi):
            if not (nome.startswith("recomp-") and nome.endswith(".json")):
                continue
            dati = await casa.get_file_contents(f"/Documents/Backup/{nome}")
            percorso = os.path.join(cartella, nome)
            if os.path.exists(percorso) and open(percorso, "rb").read() == dati:
                continue
            with open(percorso, "wb") as f:
                f.write(dati)
            copiati += 1
        print(f"Backup: {copiati} file nuovi o aggiornati copiati sul PC.")


if __name__ == "__main__":
    asyncio.run(main(sys.argv[1], sys.argv[2]))
