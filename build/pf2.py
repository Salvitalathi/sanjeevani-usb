"""Minimal GRUB PFF2 (.pf2) bitmap font writer.

GRUB fonts are 1-bit bitmaps. This renders a TrueType/OpenType font with
Pillow (hinted, non-antialiased) and writes the PFF2 container that
grub-mkfont would produce, so no grub tools are needed.
"""
import struct
from PIL import Image, ImageDraw, ImageFont


def _section(name: bytes, data: bytes) -> bytes:
    return name + struct.pack(">I", len(data)) + data


def _render_glyph(font, ch, ascent, descent):
    size = font.size
    pad = size
    w = size * 3 + pad * 2
    h = ascent + descent + pad * 2
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    d.fontmode = "1"
    base_y = pad + ascent
    d.text((pad, base_y), ch, font=font, fill=255, anchor="ls")
    adv = int(round(font.getlength(ch)))
    bbox = img.point(lambda v: 255 if v >= 128 else 0).getbbox()
    if not bbox:
        return dict(w=0, h=0, xoff=0, yoff=0, adv=adv, bits=b"")
    x0, y0, x1, y1 = bbox
    gw, gh = x1 - x0, y1 - y0
    px = img.load()
    bits = []
    for yy in range(y0, y1):
        for xx in range(x0, x1):
            bits.append(1 if px[xx, yy] >= 128 else 0)
    while len(bits) % 8:
        bits.append(0)
    out = bytearray()
    for i in range(0, len(bits), 8):
        b = 0
        for j in range(8):
            b = (b << 1) | bits[i + j]
        out.append(b)
    top = base_y - y0          # pixels above baseline
    return dict(w=gw, h=gh, xoff=x0 - pad, yoff=top - gh, adv=adv, bits=bytes(out))


def write_pf2(ttf_path, size, out_path, family, weight="normal", chars=None):
    font = ImageFont.truetype(ttf_path, size)
    ascent, descent = font.getmetrics()
    if chars is None:
        chars = [chr(c) for c in range(32, 127)]
    chars = sorted(set(chars), key=ord)
    glyphs = [(ord(c), _render_glyph(font, c, ascent, descent)) for c in chars]

    style = "Bold" if weight == "bold" else "Regular"
    name = f"{family} {style} {size}"
    head = b""
    head += _section(b"FILE", b"PFF2")
    head += _section(b"NAME", name.encode() + b"\0")
    head += _section(b"FAMI", family.encode() + b"\0")
    head += _section(b"WEIG", weight.encode() + b"\0")
    head += _section(b"SLAN", b"normal\0")
    head += _section(b"PTSZ", struct.pack(">H", size))
    head += _section(b"MAXW", struct.pack(">H", max(g["w"] for _, g in glyphs)))
    head += _section(b"MAXH", struct.pack(">H", max(g["h"] for _, g in glyphs)))
    head += _section(b"ASCE", struct.pack(">H", ascent))
    head += _section(b"DESC", struct.pack(">H", descent))

    chix_len = 9 * len(glyphs)
    data_start = len(head) + 8 + chix_len + 8   # after CHIX section and DATA header
    chix = bytearray()
    data = bytearray()
    for cp, g in glyphs:
        chix += struct.pack(">IBI", cp, 0, data_start + len(data))
        data += struct.pack(">HHhhh", g["w"], g["h"], g["xoff"], g["yoff"], g["adv"])
        data += g["bits"]
    blob = head + _section(b"CHIX", bytes(chix)) + b"DATA" + struct.pack(">I", 0xFFFFFFFF) + bytes(data)
    with open(out_path, "wb") as f:
        f.write(blob)
    return name


def read_pf2(path):
    """Parse back a .pf2 (used to verify the writer)."""
    raw = open(path, "rb").read()
    pos, info, chix = 0, {}, []
    while pos < len(raw):
        sec = raw[pos:pos + 4]; ln = struct.unpack(">I", raw[pos + 4:pos + 8])[0]; pos += 8
        if sec == b"DATA":
            break
        body = raw[pos:pos + ln]; pos += ln
        if sec == b"CHIX":
            for i in range(0, ln, 9):
                chix.append(struct.unpack(">IBI", body[i:i + 9]))
        else:
            info[sec.decode()] = body
    glyphs = {}
    for cp, flags, off in chix:
        w, h, xo, yo, adv = struct.unpack(">HHhhh", raw[off:off + 10])
        nbytes = (w * h + 7) // 8
        glyphs[cp] = (w, h, xo, yo, adv, raw[off + 10:off + 10 + nbytes])
    return info, glyphs
