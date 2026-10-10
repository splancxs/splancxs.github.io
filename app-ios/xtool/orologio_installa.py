"""Installa un'app direttamente sull'orologio (watchOS), passando dall'iPhone.

Perché: il tasto «Installa» dell'app Watch dell'iPhone non funziona con le firme gratuite (l'orologio le rifiuta se
arrivano da lì: «authorized by a free provisioning profile, but apps validated by those are not allowed to be installed
from this source»). Le accetta se arrivano da uno strumento di sviluppo, come fa Xcode: con il servizio
com.apple.streaming_zip_conduit. Il protocollo è quello di go-ios (ios/zipconduit).

L'orologio non si raggiunge da solo: si apre un canale con l'iPhone (servizio companion_proxy) e si inoltra ogni porta
dell'orologio attraverso l'iPhone. I canali vanno tenuti aperti, altrimenti l'iPhone smette di inoltrare.

Uso:  USBMUXD_SOCKET_ADDRESS=host:27015 WATCH_UDID=... python orologio_installa.py <cartella RecompWatch.app firmata>
"""
import asyncio
import os
import plistlib
import struct
import sys
import zlib
from pathlib import Path

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.service_connection import ServiceConnection
from pymobiledevice3.services.companion import CompanionProxyService

ADDR = os.environ["USBMUXD_SOCKET_ADDRESS"]
WATCH = os.environ["WATCH_UDID"]
APP = Path(sys.argv[1])
PACKAGE_TYPE = os.environ.get("PACKAGE_TYPE", "Developer")

EXTRA = bytes.fromhex("55540D0007F3A2EC60F6A2EC60F3A2EC6075780B000104F501000004" "14000000")
CENTRAL = bytes([0x50, 0x4B, 0x01, 0x02])
STD_DIR_PERM = 16877
STD_FILE_PERM = -32348


def log(*a):
    print(*a, flush=True)


def header(name: bytes, size: int, crc: int) -> bytes:
    """Intestazione «zip» locale come la vuole Apple: senza compressione e senza data descriptor."""
    return struct.pack("<IHHHHHIIIHH", 0x04034B50, 20, 0, 0, 0xBDEF, 0x52EC, crc, size, size, len(name), len(EXTRA)) \
        + name + EXTRA


def entries(app: Path):
    """(nome nello zip, dati o None per le cartelle), con prefisso Payload/."""
    out = [("Payload/", None)]
    base = app.parent
    for dp, dirs, files in os.walk(app):
        dirs.sort()
        out.append(("Payload/" + Path(dp).relative_to(base).as_posix() + "/", None))
        for f in sorted(files):
            p = Path(dp) / f
            out.append(("Payload/" + p.relative_to(base).as_posix(), p.read_bytes()))
    seen, res = set(), []
    for n, d in out:
        if n not in seen:
            seen.add(n)
            res.append((n, d))
    return res


async def main():
    iphone = await create_using_usbmux(usbmux_address=ADDR)
    comp = CompanionProxyService(iphone)
    keep = []

    async def fwd(remote_port: int) -> int:
        svc = await iphone.start_lockdown_service(comp.service_name)
        r = await svc.send_recv_plist({"Command": "StartForwardingServicePort", "GizmoRemotePortNumber": remote_port,
                                       "IsServiceLowPriority": False, "PreferWifi": False})
        keep.append(svc)
        porta = r.get("CompanionProxyServicePort")
        if not porta:
            raise RuntimeError(f"L'iPhone non riesce a raggiungere l'orologio (risposta: {r}). "
                               "Sblocca l'orologio, tienilo al polso e riprova tra qualche secondo.")
        return porta

    orologi = await comp.list()
    log("orologi abbinati all'iPhone:", orologi)
    if WATCH not in orologi:
        raise RuntimeError(f"L'orologio {WATCH} non risulta abbinato a questo iPhone: {orologi}")
    port = await fwd(62078)  # lockdown dell'orologio
    watch = await create_using_usbmux(serial=iphone.udid, identifier=WATCH, port=port, usbmux_address=ADDR,
                                      autopair=True, pair_timeout=60)
    log("collegato all'orologio:", (await watch.get_value()).get("DeviceName"))

    async def via_iphone(p: int):
        local = await fwd(p)
        return await ServiceConnection.create_using_usbmux(iphone.udid, local, usbmux_address=ADDR)

    watch.create_service_connection = via_iphone

    ents = entries(APP)
    total = sum(len(d) for _, d in ents if d is not None)
    meta = plistlib.dumps({
        "StandardDirectoryPerms": STD_DIR_PERM, "StandardFilePerms": STD_FILE_PERM,
        "RecordCount": 2 + len(ents), "TotalUncompressedBytes": total, "Version": 2,
    }, fmt=plistlib.FMT_BINARY)
    log(f"{len(ents)} elementi, {total} byte")

    svc = await watch.start_lockdown_service("com.apple.streaming_zip_conduit")
    await svc.send_plist({
        "InstallTransferredDirectory": 1,
        "UserInitiatedTransfer": 0,
        "MediaSubdir": "PublicStaging/" + APP.name + ".ipa",
        "InstallOptionsDictionary": {
            "InstallDeltaTypeKey": "InstallDeltaTypeSparseIPAFiles",
            "DisableDeltaTransfer": 1,
            "IsUserInitiated": 1,
            "PreferWifi": 1,
            "PackageType": PACKAGE_TYPE,
        },
    })
    await svc.sendall(header(b"META-INF/", 0, 0))
    await svc.sendall(header(b"META-INF/com.apple.ZipMetadata.plist", len(meta), zlib.crc32(meta)) + meta)
    for name, data in ents:
        n = name.encode()
        if data is None:
            await svc.sendall(header(n, 0, 0))
        else:
            await svc.sendall(header(n, len(data), zlib.crc32(data)) + data)
    await svc.sendall(CENTRAL)
    log("file inviati, attendo l'esito")

    while True:
        p = await asyncio.wait_for(svc.recv_plist(), timeout=180)
        if p.get("Status") == "DataComplete":
            log("installazione sull'orologio completata")
            return
        d = p.get("InstallProgressDict") or {}
        if "Error" in d:
            raise RuntimeError(f"{d.get('Error')}: {d.get('ErrorDescription')}")
        log("  ", d.get("Status"), d.get("PercentComplete"))


try:
    asyncio.run(main())
except Exception as e:  # noqa: BLE001
    if type(e).__name__ == "DeviceNotFoundError":
        log("L'orologio non risponde: è spento, lontano dall'iPhone o bloccato? Accendilo, sbloccalo, tienilo al polso e rilancia.")
    log("ERRORE:", repr(e))
    sys.exit(1)
