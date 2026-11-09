#!/usr/bin/env python3
"""
Puts the MegaZXNext badge onto the welcome screen of the on-screen display (OSD) as font characters.

The OSD is a text screen of 16x16 characters, each with one foreground and one background colour
(attribute byte: bit 7 inverse, bit 6 dark, bits 5..3 background, bits 2..0 foreground; the 16
colours come from OSM_PALETTE in globals.vhd). The badge is rebuilt from such cells: at the scale
where the four colour stripes are 16 pixels apart, each stripe lies in its own character row, so no
cell needs more than one colour on its background (the letters are made 12 % narrower so that the
badge fits into the 45 characters of the screen). The cells become characters in a copy of the M2M
font (codes the core does not print otherwise; glyphs that differ by at most 2 pixels share a code),
and the badge becomes the VHDL string SCR_LOGO in config.vhd: the characters with ESC + attribute
bytes (SCR$PRINTSTR in M2M/rom/screen.asm).

    python3 tools/osd_logo.py [--preview out.png]

Reads doc/assets/megazxnext-badge.png and M2M/font/Anikki-16x16-m2m.rom; writes
CORE/font/MegaZXNext-16x16.rom and the block between the osd_logo.py markers in CORE/vhdl/config.vhd.
Needs Pillow and numpy. Same method as tools/osd_logo.py of MegaST.

done by Chris Freeman in 2026 and licensed under GPL v3
"""

import argparse
import os
import re
from collections import Counter

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOGO = os.path.join(ROOT, 'doc/assets/megazxnext-badge.png')
FONT_IN = os.path.join(ROOT, 'M2M/font/Anikki-16x16-m2m.rom')
FONT_OUT = os.path.join(ROOT, 'CORE/font/MegaZXNext-16x16.rom')
CONFIG = os.path.join(ROOT, 'CORE/vhdl/config.vhd')

# geometry of doc/assets/megazxnext-badge.png (pixels)
L_X0, L_X1, L_Y0 = 147, 2026, 270      # letters: left and right edge, top
P_X0, P_X1 = 60, 2110                  # inside the badge (the antialiased edge is left out)
P_Y0, P_Y1 = 202, 505
STRIPE_PITCH = 45                      # the stripes are this far apart

# the badge on the OSD: cells; scale: stripe pitch -> 16 pixels, letters 12 % narrower
CW, CH = 41, 6
SY = 16 / STRIPE_PITCH
SX = SY * 0.88
TOP = 16                               # letter top in the cell canvas: the stripes fall into rows 1..4
LOGO_X = 1                             # spaces before the badge (after the frame)

# colour classes: 0 outside the badge, 1 badge grey, 2 white, 3 blue, 4 green, 5 yellow, 6 orange;
# the colours of the source and the palette index of each class in the dark half of OSM_PALETTE
# (attribute bit 6 = 1: fg = 8 + bits 2..0, bg = 8 + bits 5..3)
REF = {1: (53, 52, 51), 2: (250, 250, 250), 3: (38, 97, 253), 4: (20, 223, 51), 5: (247, 246, 42), 6: (223, 67, 1)}
DARK_IDX = {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5}      # 8 + n
ATTR_STD = 0x0B                        # M2M$SA_COL_STD: ink (index 3) on paper (index 1)
ATTR_END = 0x08                        # badge grey (index 0) on the paper (index 1)
MERGE = 2                              # glyphs that differ by at most this many pixels share a code

# font codes the core never prints: not ASCII, not the M2M frame/line/menu characters
KEEP = {0, 7, 10, 13, 16, 17, 27, 182, 185, 186, 187, 188, 196, 199, 200, 201, 204, 205, 254, 255}
FREE = [c for c in list(range(1, 32)) + list(range(127, 256)) if c not in KEEP]


def render(im):
    """the badge as colour classes on the CW x CH cell canvas"""
    refs = np.array([REF[k] for k in sorted(REF)])
    cls = ((im[:, :, None, :] - refs[None, None]) ** 2).sum(3).argmin(2) + 1
    W, H = CW * 16, CH * 16
    mx = (W - (L_X1 - L_X0) * SX) / 2
    R = H / 2
    canvas = np.zeros((H, W), int)
    for y in range(H):
        for x in range(W):
            xc = min(max(x + 0.5, R), W - R)
            if (x + 0.5 - xc) ** 2 + (y + 0.5 - R) ** 2 > R * R:
                continue
            votes = {}
            for dy in (0.17, 0.5, 0.83):
                for dx in (0.17, 0.5, 0.83):
                    xi = int(L_X0 + (x + dx - mx) / SX)
                    yi = int(L_Y0 + (y + dy - TOP) / SY)
                    k = cls[yi, xi] if P_Y0 < yi < P_Y1 and P_X0 < xi < P_X1 else 1
                    votes[k] = votes.get(k, 0) + 1
            canvas[y, x] = max(votes, key=votes.get)
    return canvas


def cells_of(canvas):
    """per cell: (fg class, bg class, 16 rows of 16 bits); one colour besides the background"""
    cells = []
    for cy in range(CH):
        row = []
        for cx in range(CW):
            c = canvas[cy * 16:(cy + 1) * 16, cx * 16:(cx + 1) * 16].copy()
            if (c == 0).any() and (c > 1).any():
                c[c == 0] = 1          # a letter in the round end: square the few pixels off
            ks, ns = np.unique(c[c > 1], return_counts=True)
            if len(ks) > 1:            # two colours: the larger part stays, the rest becomes grey
                keep = ks[ns.argmax()]
                c[(c > 1) & (c != keep)] = 1
            bg = 0 if (c == 0).any() else 1
            fgs = [k for k in np.unique(c) if k != bg]
            fg = fgs[0] if fgs else bg
            glyph = [sum(1 << (15 - x) for x in range(16) if c[y, x] == fg) for y in range(16)]
            row.append((int(fg), bg, glyph))
        cells.append(row)
    return cells


def encode(cells, font):
    """font codes and attributes of the cells; the new glyphs go into font"""
    ham = lambda a, b: sum(bin(x ^ y).count('1') for x, y in zip(a, b))
    count = Counter(tuple(g) for row in cells for _, _, g in row
                    if any(g) and not all(v == 0xFFFF for v in g))
    slots, reps = {}, []
    for t, _ in count.most_common():   # frequent glyphs first, the rare ones join a similar one
        r = next((r for r in reps if ham(t, r) <= MERGE), None)
        if r is None:
            if len(reps) == len(FREE):
                raise SystemExit('too many different logo characters')
            reps.append(t)
            slots[t] = FREE[len(reps) - 1]
            font[slots[t]] = list(t)
        else:
            slots[t] = slots[r]
    out = []
    for row in cells:
        line = []
        for fg, bg, g in row:
            t = tuple(g)
            if bg == 0:                # outside the badge: paper, badge grey as fg
                attr = ATTR_STD if not any(t) else ATTR_END
            else:                      # on the badge: dark half
                attr = 0x40 | (DARK_IDX[1] << 3) | DARK_IDX.get(fg, 0)
            if not any(t):
                code = 32
            elif all(v == 0xFFFF for v in t):   # all foreground: a space with the colour as bg
                code, attr = 32, 0x40 | (DARK_IDX[fg] << 3)
            else:
                code = slots[t]
            line.append((code, attr))
        out.append(line)
    return out, len(reps)


def vhdl(rows):
    lines = ['constant SCR_LOGO : string :=']
    for row in rows:
        parts = ['CHR_ESC & character\'val(16#%02X#) & "%s"' % (ATTR_STD, ' ' * LOGO_X)]
        cur = ATTR_STD
        for code, attr in row:
            if attr != cur:
                parts.append('CHR_ESC & character\'val(16#%02X#)' % attr)
                cur = attr
            parts.append('" "' if code == 32 else 'character\'val(%d)' % code)
        parts.append('"\\n"')
        for i in range(0, len(parts), 6):
            lines.append('   ' + ' & '.join(parts[i:i + 6]) + ' &')
    lines.append('   CHR_ESC & character\'val(16#%02X#);' % ATTR_STD)
    return lines


def main():
    ap = argparse.ArgumentParser(description='MegaZXNext badge -> OSD font characters and SCR_LOGO')
    ap.add_argument('--preview', help='also write a PNG of the badge cells (2x)')
    a = ap.parse_args()

    cells = cells_of(render(np.array(Image.open(LOGO).convert('RGB')).astype(int)))
    rom = [l.strip() for l in open(FONT_IN) if l.strip()]
    font = {c: [int(rom[c * 16 + y], 2) for y in range(16)] for c in range(256)}
    rows, n = encode(cells, font)
    os.makedirs(os.path.dirname(FONT_OUT), exist_ok=True)
    with open(FONT_OUT, 'w') as f:
        for c in range(256):
            for v in font[c]:
                f.write('{:016b}\n'.format(v))

    text = open(CONFIG).read()
    begin = '-- osd_logo.py: begin (generated by tools/osd_logo.py, do not edit)\n'
    end = '-- osd_logo.py: end\n'
    m = re.search(re.escape(begin) + '.*?' + re.escape(end), text, re.S)
    if not m:
        raise SystemExit('config.vhd: osd_logo.py markers not found')
    open(CONFIG, 'w').write(text[:m.start()] + begin + '\n'.join(vhdl(rows)) + '\n' + end + text[m.end():])
    print('%d logo characters (of %d free codes), %s, config.vhd updated' % (n, len(FREE), FONT_OUT))

    if a.preview:
        pal = {0: (255, 255, 255), 1: (52, 52, 52), 2: (250, 250, 250), 3: (38, 97, 253),
               4: (20, 223, 51), 5: (247, 246, 42), 6: (223, 67, 1)}
        img = np.zeros((CH * 16, CW * 16, 3), np.uint8)
        for cy, row in enumerate(cells):
            for cx, (fg, bg, g) in enumerate(row):
                for y in range(16):
                    for x in range(16):
                        img[cy * 16 + y, cx * 16 + x] = pal[fg] if (g[y] >> (15 - x)) & 1 else pal[bg]
        Image.fromarray(img).resize((CW * 32, CH * 32), Image.NEAREST).save(a.preview)


if __name__ == '__main__':
    main()
