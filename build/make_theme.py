"""Builds the Sanjeevani Ventoy/GRUB theme + a pixel preview rendered from the
generated .pf2 fonts (so the preview also validates the font files)."""
import math, os, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont, features

sys.path.insert(0, os.path.dirname(__file__))
from pf2 import write_pf2, read_pf2
from catalog import ISO_MENU

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "kit/ventoy/theme/sanjeevani")
os.makedirs(OUT + "/icons", exist_ok=True)

INTER = "/usr/share/fonts/opentype/inter/"
DEVA_BOLD = "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf"
FAMILY = "Sanjeevani"

ACCENT = (45, 212, 191)     # teal
BLUE = (59, 130, 246)
BG = (8, 13, 26)

# ------------------------------------------------------------------ fonts
EXTRA = "•↑↓←→–—…©®°±×"
chars = [chr(c) for c in range(32, 127)] + list(EXTRA)
FONTS = [("Regular", 16), ("Regular", 18), ("Regular", 22),
         ("Bold", 20), ("Bold", 22), ("Bold", 28)]
font_files = []
for style, size in FONTS:
    src = INTER + ("Inter-Bold.otf" if style == "Bold" else "Inter-Regular.otf")
    fn = f"{FAMILY.lower()}-{style.lower()}-{size}.pf2"
    name = write_pf2(src, size, f"{OUT}/{fn}", FAMILY,
                     weight="bold" if style == "Bold" else "normal", chars=chars)
    font_files.append(fn)
    print("font", name, fn)


# ------------------------------------------------------------- helpers
def rrect(size, radius, fill, outline=None, width=0, scale=4):
    w, h = size
    im = Image.new("RGBA", (w * scale, h * scale), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, w * scale - 1, h * scale - 1], radius * scale,
                        fill=fill, outline=outline, width=width * scale)
    return im.resize((w, h), Image.LANCZOS)


def nine_slice(img, corner, prefix):
    w, h = img.size
    c = corner
    boxes = {
        "nw": (0, 0, c, c), "n": (c, 0, w - c, c), "ne": (w - c, 0, w, c),
        "w": (0, c, c, h - c), "c": (c, c, w - c, h - c), "e": (w - c, c, w, h - c),
        "sw": (0, h - c, c, h), "s": (c, h - c, w - c, h), "se": (w - c, h - c, w, h),
    }
    for k, b in boxes.items():
        img.crop(b).save(f"{OUT}/{prefix}_{k}.png")


# ------------------------------------------------------------ background
def background(W=1920, H=1080):
    im = Image.new("RGB", (W, H), BG)
    px = im.load()
    for y in range(H):
        for x in range(0, W):
            t = y / H
            r = int(8 + 6 * t); g = int(13 + 8 * t); b = int(26 + 14 * t)
            px[x, y] = (r, g, b)
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([W * 0.62, -H * 0.45, W * 1.25, H * 0.55], fill=ACCENT + (60,))
    gd.ellipse([-W * 0.25, H * 0.55, W * 0.35, H * 1.5], fill=BLUE + (55,))
    glow = glow.filter(ImageFilter.GaussianBlur(160))
    im = Image.alpha_composite(im.convert("RGBA"), glow)
    # left panel + divider (percent based so it survives scaling)
    panel = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pd = ImageDraw.Draw(panel)
    pd.rectangle([0, 0, int(W * 0.32), H], fill=(2, 6, 16, 110))
    pd.line([int(W * 0.32), 0, int(W * 0.32), H], fill=(148, 163, 184, 40), width=2)
    # dot grid on the right side
    for y in range(40, H, 36):
        for x in range(int(W * 0.32) + 30, W, 36):
            pd.point((x, y), fill=(148, 163, 184, 22))
    im = Image.alpha_composite(im, panel)
    return im.convert("RGB")


bg = background()
bg.save(f"{OUT}/background.jpg", quality=90, optimize=True)

# --------------------------------------------------------------- pixmaps
nine_slice(rrect((96, 96), 18, (15, 23, 42, 185), (148, 163, 184, 46), 1), 20, "menu")
nine_slice(rrect((64, 64), 12, ACCENT + (46,), ACCENT + (235,), 2), 14, "select")
nine_slice(rrect((12, 40), 4, ACCENT + (210,)), 4, "scroll_thumb")
nine_slice(rrect((12, 40), 4, (148, 163, 184, 30)), 4, "scroll_frame")
nine_slice(rrect((96, 96), 14, (2, 6, 16, 235), (148, 163, 184, 60), 1), 16, "terminal_box")

# ----------------------------------------------------------------- icons
COL = {
    "rescue": (20, 184, 166), "linux": (234, 179, 8), "memory": (139, 92, 246),
    "disk": (59, 130, 246), "backup": (34, 197, 94), "boot": (249, 115, 22),
    "antivirus": (239, 68, 68), "wipe": (244, 63, 94), "installer": (14, 165, 233),
    "windows": (37, 99, 235), "tools": (100, 116, 139),
    # no vtoyiso/vtoyimg/... icons: GRUB would show them instead of the per-tool class icons
    "vtoydir": (202, 138, 4),
    "vtoyret": (71, 85, 105), "F5tool": (71, 85, 105),
}
S = 160
WHITE = (255, 255, 255, 255)
LW = 9


def glyph(name, d):
    if name in ("rescue",):
        d.rounded_rectangle([34, 40, 126, 108], 8, outline=WHITE, width=LW)
        d.line([66, 126, 94, 126], fill=WHITE, width=LW); d.line([80, 108, 80, 126], fill=WHITE, width=LW)
        d.line([80, 56, 80, 92], fill=WHITE, width=LW); d.line([62, 74, 98, 74], fill=WHITE, width=LW)
    elif name == "linux":
        d.rounded_rectangle([30, 38, 130, 122], 10, outline=WHITE, width=LW)
        d.line([50, 64, 68, 80, 50, 96], fill=WHITE, width=LW, joint="curve")
        d.line([78, 98, 108, 98], fill=WHITE, width=LW)
    elif name == "memory":
        d.rounded_rectangle([26, 54, 134, 104], 6, outline=WHITE, width=LW)
        for x in (44, 70, 96):
            d.rectangle([x, 66, x + 18, 90], fill=WHITE)
        for x in range(36, 128, 12):
            d.line([x, 104, x, 118], fill=WHITE, width=4)
    elif name == "disk":
        d.rounded_rectangle([34, 30, 126, 130], 12, outline=WHITE, width=LW)
        d.ellipse([56, 48, 104, 96], outline=WHITE, width=LW)
        d.ellipse([75, 67, 85, 77], fill=WHITE)
        d.line([54, 114, 106, 114], fill=WHITE, width=6)
    elif name == "backup":
        d.arc([36, 36, 124, 124], 200, 340, fill=WHITE, width=LW)
        d.arc([36, 36, 124, 124], 20, 160, fill=WHITE, width=LW)
        d.polygon([(118, 48), (132, 78), (104, 74)], fill=WHITE)
        d.polygon([(42, 112), (28, 82), (56, 86)], fill=WHITE)
    elif name == "boot":
        d.arc([38, 40, 122, 124], 300, 240, fill=WHITE, width=LW + 2)
        d.line([80, 28, 80, 80], fill=WHITE, width=LW + 2)
    elif name == "antivirus":
        d.polygon([(80, 26), (128, 44), (124, 92), (80, 134), (36, 92), (32, 44)], outline=WHITE, width=LW)
        d.line([58, 80, 74, 96, 104, 64], fill=WHITE, width=LW, joint="curve")
    elif name == "wipe":
        d.line([40, 50, 120, 50], fill=WHITE, width=LW)
        d.line([66, 50, 70, 36, 90, 36, 94, 50], fill=WHITE, width=6)
        d.polygon([(48, 58), (112, 58), (104, 130), (56, 130)], outline=WHITE, width=LW)
        for x in (70, 90):
            d.line([x, 72, x, 116], fill=WHITE, width=6)
    elif name == "installer":
        d.line([80, 28, 80, 96], fill=WHITE, width=LW + 2)
        d.polygon([(56, 76), (104, 76), (80, 104)], fill=WHITE)
        d.line([34, 100, 34, 128, 126, 128, 126, 100], fill=WHITE, width=LW, joint="curve")
    elif name == "windows":
        d.rounded_rectangle([28, 36, 132, 124], 8, outline=WHITE, width=LW)
        d.line([28, 60, 132, 60], fill=WHITE, width=LW)
    elif name == "tools":
        d.rounded_rectangle([28, 60, 132, 126], 8, outline=WHITE, width=LW)
        d.line([60, 60, 60, 42, 100, 42, 100, 60], fill=WHITE, width=LW)
        d.line([28, 88, 132, 88], fill=WHITE, width=6)
    elif name in ("vtoyiso", "vtoyimg", "vtoyefi", "vtoywim", "vtoyvhd"):
        d.ellipse([32, 32, 128, 128], outline=WHITE, width=LW)
        d.ellipse([68, 68, 92, 92], outline=WHITE, width=6)
    elif name == "vtoydir":
        d.polygon([(28, 50), (66, 50), (76, 62), (132, 62), (132, 120), (28, 120)], outline=WHITE, width=LW)
    elif name == "vtoyret":
        d.line([118, 112, 118, 80, 50, 80], fill=WHITE, width=LW, joint="curve")
        d.polygon([(34, 80), (62, 56), (62, 104)], fill=WHITE)
    elif name == "F5tool":
        cx = cy = 80
        for i in range(8):
            a = i * math.pi / 4
            d.line([cx + 30 * math.cos(a), cy + 30 * math.sin(a), cx + 50 * math.cos(a), cy + 50 * math.sin(a)], fill=WHITE, width=16)
        d.ellipse([44, 44, 116, 116], outline=WHITE, width=LW + 4)


for name, col in COL.items():
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    top = tuple(min(255, c + 30) for c in col)
    for y in range(S):
        t = y / S
        c = tuple(int(top[i] * (1 - t) + col[i] * t) for i in range(3))
        d.line([0, y, S, y], fill=c + (255,))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], 38, fill=255)
    im.putalpha(mask)
    g = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    glyph(name, ImageDraw.Draw(g))
    im = Image.alpha_composite(im, g)
    im.resize((40, 40), Image.LANCZOS).save(f"{OUT}/icons/{name}.png")

# ------------------------------------------------------------------ logo
assert features.check("raqm"), "need raqm for Devanagari shaping"
LOGO_W, LOGO_H = 320, 150
logo = Image.new("RGBA", (LOGO_W * 2, LOGO_H * 2), (0, 0, 0, 0))
d = ImageDraw.Draw(logo)
# shield + pulse mark
sx, sy = 0, 18
d.polygon([(sx + 60, sy), (sx + 116, sy + 20), (sx + 110, sy + 84), (sx + 60, sy + 128), (sx + 10, sy + 84), (sx + 4, sy + 20)],
          fill=ACCENT + (255,))
d.line([sx + 18, sy + 62, sx + 42, sy + 62, sx + 52, sy + 38, sx + 66, sy + 88, sx + 78, sy + 52, sx + 86, sy + 62, sx + 104, sy + 62],
       fill=BG + (255,), width=9, joint="curve")
deva = ImageFont.truetype(DEVA_BOLD, 92, layout_engine=ImageFont.Layout.RAQM)
d.text((140, 10), "संजीवनी", font=deva, fill=(255, 255, 255, 255), language="mr")
lat = ImageFont.truetype(INTER + "Inter-SemiBold.otf", 26)
x = 144
for ch in "RESCUE  USB":
    d.text((x, 150), ch, font=lat, fill=ACCENT + (255,))
    x += lat.getlength(ch) + 7
logo = logo.resize((LOGO_W, LOGO_H), Image.LANCZOS)
logo.save(f"{OUT}/logo.png")

# ------------------------------------------------------------- theme.txt
F = lambda st, sz: f'"{FAMILY} {st} {sz}"'
theme = f'''# Sanjeevani Rescue USB - Ventoy (GRUB2) theme
# All positions are percentages so the layout adapts to any resolution.
title-text: ""
desktop-image: "background.jpg"
desktop-color: "#080d1a"
terminal-font: {F("Regular", 18)}
terminal-box: "terminal_box_*.png"
terminal-left: "8%"
terminal-top: "8%"
terminal-width: "84%"
terminal-height: "84%"
terminal-border: "0"

# ---------- left brand panel ----------
+ image {{
    left = 4%
    top = 10%
    file = "logo.png"
}}
+ label {{
    left = 4%
    top = 27%
    width = 26%
    height = 30
    text = "PC Rescue & Repair Toolkit"
    font = {F("Bold", 20)}
    color = "#e2e8f0"
}}
+ label {{
    left = 4%
    top = 31%
    width = 26%
    height = 24
    text = "Free & legal tools  •  Self-updating"
    font = {F("Regular", 16)}
    color = "#64748b"
}}
+ label {{
    left = 4%
    top = 46%
    width = 26%
    height = 24
    text = "INSIDE WINDOWS"
    font = {F("Bold", 20)}
    color = "#2dd4bf"
}}
+ label {{
    left = 4%
    top = 50%
    width = 27%
    height = 24
    text = "Open the USB drive and run"
    font = {F("Regular", 16)}
    color = "#94a3b8"
}}
+ label {{
    left = 4%
    top = 53%
    width = 27%
    height = 24
    text = "START-Sanjeevani.cmd for PC Doctor"
    font = {F("Regular", 16)}
    color = "#94a3b8"
}}
+ label {{
    left = 4%
    top = 56%
    width = 27%
    height = 24
    text = "and 40+ portable repair tools."
    font = {F("Regular", 16)}
    color = "#94a3b8"
}}

# ---------- menu ----------
+ label {{
    left = 35%
    top = 10%
    width = 60%
    height = 40
    text = "Boot Menu"
    font = {F("Bold", 28)}
    color = "#ffffff"
}}
+ label {{
    left = 35%
    top = 15%
    width = 60%
    height = 24
    text = "Choose a tool with ↑ ↓ and press Enter"
    font = {F("Regular", 16)}
    color = "#64748b"
}}
+ boot_menu {{
    left = 35%
    top = 20%
    width = 60%
    height = 62%
    item_font = {F("Regular", 22)}
    item_color = "#cbd5e1"
    selected_item_font = {F("Bold", 22)}
    selected_item_color = "#ffffff"
    icon_width = 40
    icon_height = 40
    item_icon_space = 18
    item_height = 56
    item_padding = 12
    item_spacing = 6
    menu_pixmap_style = "menu_*.png"
    selected_item_pixmap_style = "select_*.png"
    scrollbar = true
    scrollbar_width = 8
    scrollbar_thumb = "scroll_thumb_*.png"
    scrollbar_frame = "scroll_frame_*.png"
}}
+ progress_bar {{
    id = "__timeout__"
    left = 35%
    top = 90%
    width = 60%
    height = 4
    show_text = false
    fg_color = "#2dd4bf"
    bg_color = "#1e293b"
    border_color = "#1e293b"
}}

# ---------- Ventoy specific ----------
+ hbox {{
    left = 35%
    top = 94%
    width = 10%
    height = 25
    + label {{text = "@VTOY_HOTKEY_TIP@" color = "#64748b" align = "left" font = {F("Regular", 16)}}}
}}
+ hbox {{
    left = 88%
    top = 4%
    width = 10%
    height = 25
    + label {{text = "@VTOY_MEM_DISK@" color = "#f43f5e" align = "left" font = {F("Bold", 20)}}}
}}
'''
open(f"{OUT}/theme.txt", "w", encoding="utf-8").write(theme)
open(f"{OUT}/fonts.list", "w").write("\n".join(font_files) + "\n")


# ---------------------------------------------------------------- preview
def pf2_text(canvas, xy, text, path, color):
    info, glyphs = _cache.setdefault(path, read_pf2(path))
    asc = int.from_bytes(info["ASCE"], "big")
    x, y = xy
    base = y + asc
    px = canvas.load()
    for ch in text:
        g = glyphs.get(ord(ch)) or glyphs.get(ord("?"))
        w, h, xo, yo, adv, bits = g
        top = base - (yo + h)
        for j in range(h):
            for i in range(w):
                k = j * w + i
                if bits[k >> 3] & (0x80 >> (k & 7)):
                    X, Y = x + xo + i, top + j
                    if 0 <= X < canvas.width and 0 <= Y < canvas.height:
                        px[X, Y] = color
        x += adv
    return x


_cache = {}


def fpath(st, sz):
    return f"{OUT}/{FAMILY.lower()}-{st.lower()}-{sz}.pf2"


def paste9(canvas, prefix, box, corner):
    x0, y0, x1, y1 = box
    p = {k: Image.open(f"{OUT}/{prefix}_{k}.png") for k in ["nw", "n", "ne", "w", "c", "e", "sw", "s", "se"]}
    c = corner
    W, H = x1 - x0, y1 - y0
    parts = [("nw", x0, y0, c, c), ("n", x0 + c, y0, W - 2 * c, c), ("ne", x1 - c, y0, c, c),
             ("w", x0, y0 + c, c, H - 2 * c), ("c", x0 + c, y0 + c, W - 2 * c, H - 2 * c), ("e", x1 - c, y0 + c, c, H - 2 * c),
             ("sw", x0, y1 - c, c, c), ("s", x0 + c, y1 - c, W - 2 * c, c), ("se", x1 - c, y1 - c, c, c)]
    for k, x, y, w, h in parts:
        if w > 0 and h > 0:
            im = p[k].resize((w, h))
            canvas.alpha_composite(im, (x, y))


def preview(W, H, out):
    cv = Image.open(f"{OUT}/background.jpg").resize((W, H)).convert("RGBA")
    P = lambda v, tot: int(tot * v / 100)
    hexc = lambda h: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5)) + (255,)
    cv.alpha_composite(Image.open(f"{OUT}/logo.png"), (P(4, W), P(10, H)))
    for top, txt, st, sz, col in [(27, "PC Rescue & Repair Toolkit", "Bold", 20, "#e2e8f0"),
                                  (31, "Free & legal tools  •  Self-updating", "Regular", 16, "#64748b"),
                                  (46, "INSIDE WINDOWS", "Bold", 20, "#2dd4bf"),
                                  (50, "Open the USB drive and run", "Regular", 16, "#94a3b8"),
                                  (53, "START-Sanjeevani.cmd for PC Doctor", "Regular", 16, "#94a3b8"),
                                  (56, "and 40+ portable repair tools.", "Regular", 16, "#94a3b8")]:
        pf2_text(cv, (P(4, W), P(top, H)), txt, fpath(st, sz), hexc(col))
    pf2_text(cv, (P(35, W), P(10, H)), "Boot Menu", fpath("Bold", 28), hexc("#ffffff"))
    pf2_text(cv, (P(35, W), P(15, H)), "Choose a tool with ↑ ↓ and press Enter", fpath("Regular", 16), hexc("#64748b"))
    mx0, my0, mw, mh = P(35, W), P(20, H), P(60, W), P(62, H)
    paste9(cv, "menu", (mx0, my0, mx0 + mw, my0 + mh), 20)
    y = my0 + 20
    for i, (cls, alias) in enumerate(ISO_MENU):
        if y + 56 > my0 + mh - 20:
            break
        sel = i == 0
        if sel:
            paste9(cv, "select", (mx0 + 20, y, mx0 + mw - 36, y + 56), 14)
        cv.alpha_composite(Image.open(f"{OUT}/icons/{cls}.png"), (mx0 + 32, y + 8))
        f = fpath("Bold" if sel else "Regular", 22)
        pf2_text(cv, (mx0 + 32 + 40 + 18, y + 14), alias, f, hexc("#ffffff" if sel else "#cbd5e1"))
        y += 56 + 6
    # scrollbar
    paste9(cv, "scroll_frame", (mx0 + mw - 26, my0 + 20, mx0 + mw - 18, my0 + mh - 20), 4)
    paste9(cv, "scroll_thumb", (mx0 + mw - 26, my0 + 20, mx0 + mw - 18, my0 + int(mh * 0.6)), 4)
    pf2_text(cv, (P(35, W), P(85, H)), "Windows rescue desktop: password reset, data backup, driver backup",
             fpath("Regular", 16), hexc("#94a3b8"))
    pf2_text(cv, (P(35, W), P(94, H)), "F1:Help  F2:Browse  F3:TreeView  F4:Localboot  F5:Tools  F6:ExMenu",
             fpath("Regular", 16), hexc("#64748b"))
    pf2_text(cv, (P(4, W), P(95, H)), "1.1.x UEFI  www.ventoy.net", fpath("Regular", 16), hexc("#475569"))
    cv.convert("RGB").save(out)


os.makedirs(os.path.join(ROOT, "docs"), exist_ok=True)
preview(1920, 1080, os.path.join(ROOT, "docs/boot-menu-preview-1080p.png"))
preview(1024, 768, os.path.join(ROOT, "docs/boot-menu-preview-1024x768.png"))
print("ok")
