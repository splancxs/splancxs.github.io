"""Una tantum: abbina il PC all'orologio (attraverso l'iPhone) e fa comparire la Modalità sviluppatore.

Uso (con l'iPhone collegato al PC, l'orologio sbloccato e al polso):
  USBMUXD_SOCKET_ADDRESS=host:27015 WATCH_UDID=... python orologio_sviluppatore.py info      mostra modello e stato
  ...                                                       python orologio_sviluppatore.py reveal    fa comparire l'interruttore
Poi sull'orologio: Impostazioni → Privacy e sicurezza → Modalità sviluppatore → attivala (si riavvia).
La prima volta l'orologio chiede «Autorizza questo computer?» (compare come «localhost»).
"""
import asyncio
import os
import sys

from pymobiledevice3.lockdown import create_using_usbmux
from pymobiledevice3.service_connection import ServiceConnection
from pymobiledevice3.services.amfi import AmfiService
from pymobiledevice3.services.companion import CompanionProxyService

ADDR = os.environ["USBMUXD_SOCKET_ADDRESS"]


def log(*a):
    print(*a, flush=True)


async def main():
    azione = sys.argv[1] if len(sys.argv) > 1 else "info"
    # l'orologio si raggiunge solo con l'iPhone collegato via USB (via Wi-Fi companion_proxy chiude la connessione)
    iphone = await create_using_usbmux(usbmux_address=ADDR, connection_type="USB")
    comp = CompanionProxyService(iphone)
    orologi = await comp.list()
    log("orologi abbinati all'iPhone:", orologi)
    watch_udid = os.environ.get("WATCH_UDID") or orologi[0]
    keep = []

    async def fwd(remote_port: int) -> int:
        svc = await iphone.start_lockdown_service(comp.service_name)
        r = await svc.send_recv_plist({"Command": "StartForwardingServicePort", "GizmoRemotePortNumber": remote_port,
                                       "IsServiceLowPriority": False, "PreferWifi": False})
        keep.append(svc)
        return r.get("CompanionProxyServicePort")

    port = await fwd(62078)
    watch = await create_using_usbmux(serial=iphone.udid, identifier=watch_udid, port=port, usbmux_address=ADDR,
                                      autopair=True, pair_timeout=120)

    async def via_iphone(p: int):
        local = await fwd(p)
        return await ServiceConnection.create_using_usbmux(iphone.udid, local, usbmux_address=ADDR)

    watch.create_service_connection = via_iphone
    v = await watch.get_value()
    for k in ("DeviceName", "ProductType", "ProductVersion", "UniqueDeviceID"):
        log(" ", k, "=", v.get(k))
    log("  Modalità sviluppatore:", await watch.get_value("com.apple.security.mac.amfi", "DeveloperModeStatus"))
    if azione == "reveal":
        await AmfiService(watch).reveal_developer_mode_option_in_ui()
        log("fatto: ora l'interruttore è visibile sull'orologio")


try:
    asyncio.run(main())
except Exception as e:  # noqa: BLE001
    log("ERRORE:", repr(e))
    sys.exit(1)
