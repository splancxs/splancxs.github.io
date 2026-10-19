#!/usr/bin/env python3
"""Converte il piano alimentare e le schede (assets/js/data.js, generato da genera_piano.py) nel file JSON che legge
l'app SwiftUI: app-ios/swiftui/Resources/piano.json. Le forme «ad array misto» di data.js diventano oggetti, così Swift
le decodifica senza codice speciale. Da rilanciare dopo ogni genera_piano.py."""
import json
from pathlib import Path

radice = Path(__file__).resolve().parent.parent
sorgente = (radice / "assets" / "js" / "data.js").read_text(encoding="utf-8")
d = json.loads(sorgente[sorgente.index("{"):sorgente.rindex("}") + 1])

piano = {
    "version": d["version"],
    "foods": d["foods"],
    "recipes": d["recipes"],
    # slot → codice → [{f: alimento, g: grammi}]
    "variants": {slot: {codice: [{"f": f, "g": g} for f, g in righe] for codice, righe in varianti.items()}
                 for slot, varianti in d["variants"].items()},
    # fasce orarie: [orario, nome, slot] → oggetto
    "daytypes": {k: {"label": v["label"], "target": v["target"],
                     "slots": [{"time": t, "label": n, "slot": s} for t, n, s in v["slots"]]}
                 for k, v in d["daytypes"].items()},
    "week": d["week"],
    "workouts": d["workouts"],
    "exlib": d["exlib"],
    "muscleTargets": d["muscleTargets"],
    "equivalents": d["equivalents"],
}

uscita = radice / "app-ios" / "swiftui" / "Resources" / "piano.json"
uscita.parent.mkdir(parents=True, exist_ok=True)
uscita.write_text(json.dumps(piano, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
print(f"scritto {uscita} ({uscita.stat().st_size} byte)")
