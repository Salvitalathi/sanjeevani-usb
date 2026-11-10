"""Builds the Sanjeevani app icon (PC Doctor window / taskbar) from the same shield + pulse mark as the
boot-menu logo:  kit/Sanjeevani/PCDoctor/assets/sanjeevani.ico (16-256 px) and logo-256.png.
Run:  python3 build/make_icon.py"""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'kit', 'Sanjeevani', 'PCDoctor', 'assets')
os.makedirs(OUT, exist_ok=True)

TOP, BOTTOM = (94, 234, 212), (13, 148, 136)      # #5EEAD4 -> #0D9488
INK = (11, 18, 32)                                  # #0B1220


def mark(size, line_scale=1.0):
    S = 1024
    im = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    # shield geometry from the boot logo (120 x 128 box), centred
    k = S / 136.0
    ox, oy = (S - 120 * k) / 2, (S - 128 * k) / 2
    P = lambda x, y: (ox + x * k, oy + y * k)
    shield = [P(60, 0), P(116, 20), P(110, 84), P(60, 128), P(10, 84), P(4, 20)]
    grad = Image.new('RGBA', (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / (S - 1)
        gd.line([(0, y), (S, y)], fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,))
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).polygon(shield, fill=255)
    im.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(im)
    pts = [P(18, 62), P(42, 62), P(52, 38), P(66, 88), P(78, 52), P(86, 62), P(104, 62)]
    w = int(9 * k * line_scale)
    d.line(pts, fill=INK + (255,), width=w, joint='curve')
    for p in (pts[0], pts[-1]):
        d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=INK + (255,))
    return im.resize((size, size), Image.LANCZOS)


sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
# small sizes get a thicker pulse line so it stays visible
imgs = [mark(s, 1.45 if s <= 24 else 1.2 if s <= 48 else 1.0) for s in sizes]
imgs[-1].save(os.path.join(OUT, 'sanjeevani.ico'), format='ICO', sizes=[(s, s) for s in sizes], append_images=imgs[:-1])
mark(256).save(os.path.join(OUT, 'logo-256.png'))
print('icon written:', os.listdir(OUT))
