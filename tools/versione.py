"""Alza la versione del sito: ?v= in index.html e sw.js e il nome della cache del service worker.
Va lanciato a ogni rilascio che cambia index.html o assets/, altrimenti telefono e PC tengono i file vecchi.
Uso: python tools/versione.py        (versione attuale + 1)
     python tools/versione.py 60     (versione precisa)
"""
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FILES = [ROOT / 'index.html', ROOT / 'sw.js']

cur = max(int(v) for v in re.findall(r'\?v=(\d+)', (ROOT / 'index.html').read_text(encoding='utf-8')))
new = int(sys.argv[1]) if len(sys.argv) > 1 else cur + 1
for f in FILES:
    t = f.read_text(encoding='utf-8')
    t = re.sub(r'\?v=\d+', f'?v={new}', t)
    t = re.sub(r"'recomp-v\d+'", f"'recomp-v{new - 1}'", t)
    with io.open(f, 'w', encoding='utf-8', newline='\n') as out:
        out.write(t)
print(f'versione {cur} -> {new}')
