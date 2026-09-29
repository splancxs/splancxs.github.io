# Genera le icone PNG del sito (manubrio lime su fondo scuro). Uso: python tools/genera_icone.py
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'assets', 'icons')
BG, FG = (20, 20, 20, 255), (196, 240, 49, 255)


def icon(size, pad_ratio=0.0, radius_ratio=0.22):
    s = 4 * size  # supersampling per bordi puliti
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if pad_ratio == 0:
        d.rounded_rectangle([0, 0, s - 1, s - 1], radius=int(s * radius_ratio), fill=BG)
    else:
        d.rectangle([0, 0, s - 1, s - 1], fill=BG)
    u = s / 64 * (1 - 2 * pad_ratio)
    o = s * pad_ratio

    def r(x, y, w, h):
        d.rounded_rectangle([o + x * u, o + y * u, o + (x + w) * u, o + (y + h) * u], radius=int(2 * u), fill=FG)

    r(10, 22, 7, 20); r(47, 22, 7, 20); r(17, 17, 7, 30); r(40, 17, 7, 30); r(24, 29, 16, 6)
    return im.resize((size, size), Image.LANCZOS)


def splash(w, h):
    """Schermata di avvio iOS: icona al centro e scritta 'recomp.' sotto."""
    from PIL import ImageFont
    im = Image.new('RGB', (w, h), (13, 14, 15))
    size = int(w * 0.30)
    ic = icon(size)
    x, y = (w - size) // 2, int(h * 0.40) - size // 2
    im.paste(ic, (x, y), ic)
    d = ImageDraw.Draw(im)
    try:
        font = ImageFont.truetype(r'C:\Windows\Fonts\segoeuib.ttf', int(w * 0.075))
    except OSError:
        font = ImageFont.load_default()
    word, dot = 'recomp', '.'
    ww = d.textlength(word, font=font)
    wd = d.textlength(dot, font=font)
    tx, ty = (w - ww - wd) / 2, y + size + int(w * 0.06)
    d.text((tx, ty), word, font=font, fill=(241, 241, 236))
    d.text((tx + ww, ty), dot, font=font, fill=FG[:3])
    return im


os.makedirs(OUT, exist_ok=True)
icon(192).save(os.path.join(OUT, 'icon-192.png'))
icon(512).save(os.path.join(OUT, 'icon-512.png'))
icon(512, pad_ratio=0.12).save(os.path.join(OUT, 'icon-maskable-512.png'))
icon(180, pad_ratio=0.0, radius_ratio=0).save(os.path.join(OUT, 'apple-touch-icon.png'))
splash(1170, 2532).save(os.path.join(OUT, 'splash-1170x2532.png'), optimize=True)

# App nativa iOS (app-ios/resources): icona 1024 quadrata senza trasparenza (iOS arrotonda da sé) e splash 2732
RES = os.path.join(ROOT, 'app-ios', 'resources')
os.makedirs(RES, exist_ok=True)
icon(1024, radius_ratio=0).convert('RGB').save(os.path.join(RES, 'icon-1024.png'))
splash(2732, 2732).save(os.path.join(RES, 'splash-2732.png'), optimize=True)
print('icone generate in', OUT)
