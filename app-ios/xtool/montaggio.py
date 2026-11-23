# Affianca gli screenshot del giro di controllo a tre a tre (ridotti) in fogli JPG, per guardarli in una volta.
#   montaggio.py <cartella>       usa tutti i .png della cartella, in ordine di nome, e scrive <cartella>/foglio_N.jpg
# Gli screenshot ridotti ingannano sui dettagli piccoli: per quelli si guarda il .png intero.
import sys
from pathlib import Path
from PIL import Image

cartella = Path(sys.argv[1])
foto = sorted(cartella.glob("*.png"))
L = 560
for vecchio in cartella.glob("foglio_*.jpg"):
    vecchio.unlink()
for k in range(0, len(foto), 3):
    gruppo = []
    for f in foto[k:k + 3]:
        i = Image.open(f).convert("RGB")
        gruppo.append(i.resize((L, int(i.height * L / i.width))))
    H = max(i.height for i in gruppo)
    tela = Image.new("RGB", (L * len(gruppo) + 20 * (len(gruppo) - 1), H), (60, 60, 60))
    for j, i in enumerate(gruppo):
        tela.paste(i, (j * (L + 20), 0))
    uscita = cartella / f"foglio_{k // 3 + 1}.jpg"
    tela.save(uscita, quality=80)
    print(uscita.name, " ".join(f.stem for f in foto[k:k + 3]))
