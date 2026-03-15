#!/usr/bin/env python3
"""
Scripts/make_icns.py
Génère Resources/AppIcon.icns depuis Resources/AppIcon.svg.
Dépendances : Pillow (pip install Pillow)
Usage       : python3 Scripts/make_icns.py
"""

import math
import os
import struct
import sys
import tempfile
from pathlib import Path

# ── Vérifier Pillow ───────────────────────────────────────────
try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    print("✗ Pillow requis : pip3 install Pillow", file=sys.stderr)
    sys.exit(1)

ROOT      = Path(__file__).parent.parent
SVG_PATH  = ROOT / "Resources" / "AppIcon.svg"
ICNS_PATH = ROOT / "Resources" / "AppIcon.icns"

# Tailles requises pour un .icns macOS complet
SIZES = [16, 32, 64, 128, 256, 512, 1024]

# ── Rendu vectoriel du D (même logique que le SVG) ────────────

def cubic_bezier(p0, p1, p2, p3, n=120):
    pts = []
    for i in range(n + 1):
        t = i / n; mt = 1 - t
        x = mt**3*p0[0] + 3*mt**2*t*p1[0] + 3*mt*t**2*p2[0] + t**3*p3[0]
        y = mt**3*p0[1] + 3*mt**2*t*p1[1] + 3*mt*t**2*p2[1] + t**3*p3[1]
        pts.append((x, y))
    return pts


def render_icon(size: int) -> Image.Image:
    sc = size / 1024.0

    def s(x, y):
        return (x * sc, y * sc)

    # ── Fond dégradé bleu ──────────────────────────────────────
    img  = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / max(size - 1, 1)
        r = int(21  + (13  - 21)  * t)
        g = int(101 + (71  - 101) * t)
        b = int(192 + (161 - 192) * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    # Coins arrondis
    radius = int(224 * sc)
    mask   = Image.new("L", (size, size), 0)
    md     = ImageDraw.Draw(mask)
    md.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    img.putalpha(mask)

    # ── Lettre D ──────────────────────────────────────────────
    outer = [s(210, 172), s(400, 172)]
    outer += cubic_bezier(s(400, 172), s(590, 172), s(790, 312), s(790, 512))[1:]
    outer += cubic_bezier(s(790, 512), s(790, 712), s(590, 852), s(400, 852))[1:]
    outer.append(s(210, 852))

    inner = [s(330, 300), s(400, 300)]
    inner += cubic_bezier(s(400, 300), s(555, 300), s(660, 392), s(660, 512))[1:]
    inner += cubic_bezier(s(660, 512), s(660, 632), s(555, 724), s(400, 724))[1:]
    inner.append(s(330, 724))
    inner.reverse()

    d_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dd      = ImageDraw.Draw(d_layer)
    dd.polygon(outer, fill=(255, 255, 255, 255))
    dd.polygon(inner, fill=(0, 0, 0, 0))

    # Ombre portée
    blur       = max(1, int(9 * sc))
    shadow_raw = d_layer.filter(ImageFilter.GaussianBlur(blur))
    shadow     = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    for px, py in ((x, y) for x in range(size) for y in range(size)):
        pass  # éviter boucle pixel — utiliser getdata
    raw = list(shadow_raw.getdata())
    shadow.putdata([(0, 0, 0, min(int(a * 0.32), 255)) for r, g, b, a in raw])
    shifted = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shifted.paste(shadow, (0, max(1, int(4 * sc))))

    # Reflet
    gloss = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    gd    = ImageDraw.Draw(gloss)
    gd.ellipse(
        [int(25 * sc), int(15 * sc), int(500 * sc), int(350 * sc)],
        fill=(255, 255, 255, 14)
    )

    result = Image.alpha_composite(img, shifted)
    result = Image.alpha_composite(result, d_layer)
    result = Image.alpha_composite(result, gloss)
    return result


# ── Assemblage du fichier .icns ───────────────────────────────
# Format ICNS : magic 'icns' + taille totale (big-endian uint32)
# suivi de blocs : OSType (4 octets) + taille bloc (4 octets) + données PNG

# Correspondance taille → OSType Apple
OSTYPE = {
    16:   b"icp4",
    32:   b"icp5",
    64:   b"icp6",
    128:  b"ic07",
    256:  b"ic08",
    512:  b"ic09",
    1024: b"ic10",
}


def make_icns(output_path: Path):
    print(f"→ Génération de {output_path.name}")
    blocks = b""

    for size in SIZES:
        print(f"  Rendu {size}×{size}px…", end=" ", flush=True)
        img = render_icon(size)

        # Encoder en PNG en mémoire
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as tmp:
            tmp_path = tmp.name
        img.save(tmp_path, "PNG")
        with open(tmp_path, "rb") as f:
            png_data = f.read()
        os.unlink(tmp_path)

        ostype     = OSTYPE[size]
        block_size = 8 + len(png_data)          # header 8 octets + données
        blocks    += ostype + struct.pack(">I", block_size) + png_data
        print(f"{len(png_data) // 1024} Ko")

    total_size = 8 + len(blocks)                 # magic + taille + blocs
    icns_data  = b"icns" + struct.pack(">I", total_size) + blocks

    output_path.write_bytes(icns_data)
    print(f"  ✓ {output_path} ({total_size // 1024} Ko)")


if __name__ == "__main__":
    if not SVG_PATH.exists():
        print(f"✗ SVG introuvable : {SVG_PATH}", file=sys.stderr)
        sys.exit(1)
    make_icns(ICNS_PATH)
