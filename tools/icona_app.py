# Icona dell'app nei colori nuovi: grafite, manubrio argento metallico (variante con l'impugnatura rossa)
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
import sys

S = 4            # sovracampionamento per bordi lisci
N = 1024 * S
out = sys.argv[1]
variante = sys.argv[2] if len(sys.argv) > 2 else "argento"

def hexrgb(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], dtype=float)

# sfondo: grafite con una luce morbida in alto a sinistra
yy, xx = np.mgrid[0:N, 0:N].astype(float) / N
d = np.sqrt((xx - 0.38) ** 2 + (yy - 0.30) ** 2)
t = np.clip(d / 0.95, 0, 1)[..., None]
fondo = hexrgb(0x2C2C31) * (1 - t) + hexrgb(0x0F0F11) * t

# forma del manubrio (stesse misure dell'icona di prima)
def forma(rects):
    m = Image.new("L", (N, N), 0)
    dr = ImageDraw.Draw(m)
    for x0, y0, x1, y1 in rects:
        dr.rounded_rectangle([x0 * S, y0 * S, x1 * S, y1 * S], radius=32 * S, fill=255)
    return np.array(m, dtype=float)[..., None] / 255

dischi = [(160, 352, 272, 672), (272, 272, 384, 752), (640, 272, 752, 752), (752, 352, 864, 672)]
manico = [(376, 464, 648, 560)]
m_dischi = forma(dischi)
m_manico = forma(manico)

# argento metallico: le stesse sfumature della scheda «Adesso» (in diagonale, con riflessi)
stops = [(0.00, 0xE6E8E7), (0.22, 0xFFFFFF), (0.42, 0xA9ACAB), (0.58, 0xD3D5D4), (0.80, 0x8E9190), (1.00, 0xC2C4C3)]
u = np.clip((xx * 0.55 + yy * 0.85 - 0.25) / 0.95, 0, 1)
argento = np.zeros((N, N, 3))
for (a, ca), (b, cb) in zip(stops, stops[1:]):
    sel = (u >= a) & (u <= b)
    k = ((u - a) / (b - a))[..., None]
    argento[sel] = (hexrgb(ca) * (1 - k) + hexrgb(cb) * k)[sel]

if variante == "rosso":
    # impugnatura rossa con un riflesso in alto
    v = np.clip((yy * 1024 - 464) / 96, 0, 1)[..., None]
    manico_col = hexrgb(0xF06A5E) * (1 - v) + hexrgb(0xC23A2E) * v
else:
    manico_col = argento * 0.82

img = fondo * (1 - m_dischi) + argento * m_dischi
img = img * (1 - m_manico) + manico_col * m_manico

# ombra sotto il manubrio (leggera, per staccarlo dal fondo)
ombra = Image.fromarray((np.clip(m_dischi + m_manico, 0, 1)[..., 0] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(28 * S))
ombra = np.array(ombra, dtype=float)[..., None] / 255
ombra = np.roll(ombra, 18 * S, axis=0)
fuori = 1 - np.clip(m_dischi + m_manico, 0, 1)
img = img * (1 - 0.55 * ombra * fuori)

Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).save(out)
print("ok", out)
