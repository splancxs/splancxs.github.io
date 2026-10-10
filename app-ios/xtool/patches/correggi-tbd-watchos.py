"""Corregge i file di descrizione delle librerie (.tbd) dell'SDK watchOS.

I .tbd di watchOS 27 citano un tipo di processore nuovo («arm64e.x1-watchos») che il linker lld di xtool (LLVM 21.1.6)
non conosce: senza questa correzione il collegamento dice «malformed file / unknown target». Si toglie quel tipo dagli
elenchi (nella copia dell'SDK costruita da xtool, mai nell'Xcode originale).

Uso:  python correggi-tbd-watchos.py <cartella di WatchOS27.0.sdk>
"""
import os
import re
import sys

root = sys.argv[1]
tok = "arm64e.x1-watchos"
n = 0
for dp, _, fn in os.walk(root):
    for f in fn:
        if not f.endswith(".tbd"):
            continue
        p = os.path.join(dp, f)
        try:
            s = open(p, encoding="utf-8", newline="").read()
        except UnicodeDecodeError:
            continue
        if tok not in s:
            continue
        o = s
        s = re.sub(r"\[\s*" + re.escape(tok) + r"\s*\]", "[ arm64e-watchos ]", s)   # lista di un solo elemento
        s = re.sub(re.escape(tok) + r"\s*,\s*", "", s)                              # all'inizio o in mezzo
        s = re.sub(r"\s*,\s*" + re.escape(tok), "", s)                              # in fondo
        s = s.replace(tok, "arm64e-watchos")                                        # eventuali residui
        if s != o:
            open(p, "w", encoding="utf-8", newline="").write(s)
            n += 1
print("file corretti:", n)
