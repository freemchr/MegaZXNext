#!/usr/bin/env python3
# MegaZXNext: converts the MegaZXNext badge (doc/assets/megazxnext-badge.png) into the logo part
# of a ZX Spectrum screen (6912 bytes, .scr) for the ZX Next firmware boot screen.
#
# The ULA allows one ink colour per 8x8 cell, so the logo is laid out on the cell grid instead
# of being scaled as a whole: "MegaZX" and "Next" are scaled from the badge, the four colour
# stripes are drawn so that each one lies in its own character row (7 pixel pitch), and the
# dark grey badge, which the ULA cannot show, becomes a grey outline. Character row 23 gets the
# credit line in the small font of the original screen. Only the rows LOGO_ROWS are used;
# zxn_bootscreen.py keeps the rest of the original screen.
#
# Usage: make_logo.py badge.png megazxnext.scr [preview.png]
#
# done by Chris Freeman in 2026 and licensed under GPL v3

import struct
import sys
import zlib

LOGO_ROWS = list(range(10)) + [23]  # character rows replaced: logo, credit line

# Credit line (row 23): text and ULA colour. A colour change starts a new character cell.
CREDIT = [('Ported by: ', 7), ('Chris Freeman', 2), (' with features from ', 7), ('@Benitoss', 2)]

# The small font of the firmware screens: 7 pixel rows (y = 184..190 in row 23), mostly copied
# from the original credit line; C, F, a, f, h, m, u and w drawn in the same style.
FONT = {
   ' ': ['...'] * 7,
   ':': ['.', '.', '.', '#', '.', '#', '.'],
   '@': ['.....', '.###.', '....#', '###.#', '#.#.#', '#...#', '.###.'],
   'B': ['....', '###.', '#..#', '###.', '#..#', '#..#', '###.'],
   'C': ['....', '.###', '#...', '#...', '#...', '#...', '.###'],
   'F': ['....', '####', '#...', '###.', '#...', '#...', '#...'],
   'P': ['....', '###.', '#..#', '#..#', '###.', '#...', '#...'],
   'a': ['....', '....', '.##.', '...#', '.###', '#..#', '.###'],
   'b': ['....', '#...', '###.', '#..#', '#..#', '#..#', '####'],
   'd': ['....', '...#', '.###', '#..#', '#..#', '#..#', '####'],
   'e': ['....', '....', '.##.', '#..#', '####', '#...', '.###'],
   'f': ['...', '.##', '#..', '###', '#..', '#..', '#..'],
   'h': ['....', '#...', '###.', '#..#', '#..#', '#..#', '#..#'],
   'i': ['#', '.', '#', '#', '#', '#', '#'],
   'm': ['.....', '.....', '####.', '#.#.#', '#.#.#', '#.#.#', '#.#.#'],
   'n': ['....', '....', '#.##', '##.#', '#..#', '#..#', '#..#'],
   'o': ['....', '....', '.##.', '#..#', '#..#', '#..#', '.##.'],
   'r': ['...', '...', '#.#', '##.', '#..', '#..', '#..'],
   's': ['....', '....', '.##.', '#...', '.##.', '...#', '.##.'],
   't': ['...', '#..', '##.', '#..', '#..', '#..', '.##'],
   'u': ['....', '....', '#..#', '#..#', '#..#', '#..#', '.###'],
   'w': ['.....', '.....', '#...#', '#...#', '#.#.#', '#.#.#', '.#.#.'],
   'y': ['...', '...', '#.#', '#.#', '###', '..#', '##.'],
}

CAP     = 19                        # height of the capitals in pixels
ROW0    = 2                         # character row of the first (blue) stripe
STRIPES = [1, 4, 6, 2]              # blue, green, yellow, red (ULA colours)
LEFT    = [3, 0, 2, 4]              # start of each stripe: the left ends form a chevron


def read_png(name):
   """Minimal PNG reader (8 bit RGB/RGBA, not interlaced). Returns w, h, rows of (r,g,b,a)."""
   data = open(name, 'rb').read()
   assert data[:8] == b'\x89PNG\r\n\x1a\n', 'not a PNG file'
   pos, idat = 8, b''
   while pos < len(data):
      ln, typ = struct.unpack('>I4s', data[pos:pos + 8])
      body = data[pos + 8:pos + 8 + ln]
      if typ == b'IHDR':
         w, h, depth, ctype, _, _, inter = struct.unpack('>IIBBBBB', body)
         assert depth == 8 and ctype in (2, 6) and inter == 0, 'need 8 bit RGB/RGBA PNG'
         bpp = 4 if ctype == 6 else 3
      elif typ == b'IDAT':
         idat += body
      pos += 12 + ln
   raw, stride, prev, rows = zlib.decompress(idat), w * bpp, bytearray(w * bpp), []
   for y in range(h):
      f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
      for i in range(stride):
         a = line[i - bpp] if i >= bpp else 0
         b, c = prev[i], prev[i - bpp] if i >= bpp else 0
         if f == 1:
            line[i] = (line[i] + a) & 255
         elif f == 2:
            line[i] = (line[i] + b) & 255
         elif f == 3:
            line[i] = (line[i] + (a + b) // 2) & 255
         elif f == 4:
            p = a + b - c
            pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
            line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
      rows.append([tuple(line[x * bpp:x * bpp + 3]) + ((line[x * bpp + 3],) if bpp == 4 else (255,))
                   for x in range(w)])
      prev = line
   return w, h, rows


def letter_mask(w, h, rows):
   """White, opaque pixels = letters."""
   return [[r > 180 and g > 180 and b > 180 and a > 128 and max(r, g, b) - min(r, g, b) < 50
            for (r, g, b, a) in row] for row in rows]


def bbox_columns(mask, w, h):
   """Column ranges of the letter groups: "MegaZX" and "Next" are separated by the stripes."""
   cols = [any(mask[y][x] for y in range(0, h, 2)) for x in range(w)]
   xs = [x for x in range(w) if cols[x]]
   gaps, run = [], None
   for x in range(xs[0], xs[-1] + 1):
      if not cols[x]:
         run = x if run is None else run
      else:
         if run is not None:
            gaps.append((x - run, run, x))
         run = None
   widest = max(gaps)
   return (xs[0], widest[1]), (widest[2], xs[-1] + 1)


def scale(mask, x0, x1, y0, y1, s):
   """Area-average the mask box [x0,x1)x[y0,y1) by factor s, threshold at one half."""
   tw, th = round((x1 - x0) * s), round((y1 - y0) * s)
   out = []
   for ty in range(th):
      sy0, sy1 = y0 + int(ty / s), min(y1, y0 + int((ty + 1) / s))
      line = []
      for tx in range(tw):
         sx0, sx1 = x0 + int(tx / s), min(x1, x0 + int((tx + 1) / s))
         n = sum(mask[y][x] for y in range(sy0, sy1) for x in range(sx0, sx1))
         line.append(2 * n >= (sy1 - sy0) * (sx1 - sx0))
      out.append(line)
   return out


def make_logo(name):
   w, h, rows = read_png(name)
   mask = letter_mask(w, h, rows)
   (ax0, ax1), (bx0, bx1) = bbox_columns(mask, w, h)
   ys = [y for y in range(h) if any(mask[y][x] for x in range(ax0, ax0 + 40))]   # the "M"
   cap_top, cap_h = ys[0], ys[-1] + 1 - ys[0]
   bottom = max(y for y in range(h) if any(mask[y]))                              # the "g"
   s = CAP / cap_h
   mega = scale(mask, ax0, ax1, cap_top, bottom + 1, s)
   nxt = scale(mask, bx0, bx1, cap_top, bottom + 1, s)

   # Horizontal layout: the stripes get three character columns of their own, so that no cell
   # holds both a white letter and a coloured stripe. Centre the whole on the screen.
   # Stripes at x = 8*sc+1 .. 8*sc+21, the letters 3 pixels away on both sides.
   wm, wn = len(mega[0]), len(nxt[0])
   sc = round((234 + wm - wn) / 16)                                 # first stripe column
   mx = sc * 8 - 3 - wm
   nx = sc * 8 + 25
   top = ROW0 * 8 + 7                                              # cap top, see stripes below

   ink = [[None] * 256 for _ in range(192)]                        # (colour, bright) per pixel
   for img, x0 in ((mega, mx), (nxt, nx)):
      for y, line in enumerate(img):
         for x, on in enumerate(line):
            if on:
               ink[top + y][x0 + x] = (7, True)

   # Stripes: 3 pixels high at a 7 pixel pitch, stripe k in character row ROW0 + k.
   for k, col in enumerate(STRIPES):
      for dy in range(3):
         y = ROW0 * 8 + 5 + 7 * k + dy
         slant = (2 - dy) if k == 0 else dy if k >= 2 else abs(1 - dy)
         for x in range(sc * 8 + 1 + LEFT[k] + slant // 2, sc * 8 + 22):
            ink[y][x] = (col, True)

   # The badge outline: a stadium around the text, grey (white without BRIGHT).
   px0, px1 = mx - 11, nx + wn + 11
   assert px0 >= 0 and px1 < 256, f'logo too wide: {px0}..{px1}'
   py0, py1 = top - 9, top + 9 + CAP + 8
   r = (py1 - py0) / 2
   cy = (py0 + py1) / 2

   def inside(x, y, d):
      cx = min(max(x, px0 + r), px1 - r)
      return (x - cx) ** 2 + (y - cy) ** 2 <= (r - d) ** 2

   for y in range(py0, py1 + 1):
      for x in range(max(0, px0 - 1), min(256, px1 + 2)):
         if inside(x + .5, y + .5, 0) and not inside(x + .5, y + .5, 1.2) and ink[y][x] is None:
            ink[y][x] = (7, False)

   # Credit line, at the position of the original one.
   x, last = 11, None
   for text, col in CREDIT:
      if last is not None and last // 8 == x // 8:
         x = (x // 8 + 1) * 8                                      # new colour: new cell
      for ch in text:
         glyph = FONT[ch]
         for dy, line in enumerate(glyph):
            for dx, p in enumerate(line):
               if p == '#':
                  ink[184 + dy][x + dx] = (col, True)
                  last = x + dx
         x += len(glyph[0]) + 1
   assert x <= 256, 'credit line too long'

   scr = bytearray(6912)
   for cy_ in LOGO_ROWS:
      for cx_ in range(32):
         cell = [ink[cy_ * 8 + y][cx_ * 8 + x] for y in range(8) for x in range(8)]
         used = [c for c in cell if c]
         colours = {c[0] for c in used}
         assert len(colours) <= 1, f'attribute clash in cell {cx_},{cy_}: {colours}'
         colour = used[0][0] if used else 0
         bright = any(c[1] for c in used)
         scr[6144 + cy_ * 32 + cx_] = colour | (0x40 if bright or not used else 0)
         for y in range(8):
            yy = cy_ * 8 + y
            addr = ((yy & 0xc0) << 5) | ((yy & 7) << 8) | ((yy & 0x38) << 2) | cx_
            scr[addr] = sum(0x80 >> x for x in range(8) if ink[yy][cx_ * 8 + x])
   return bytes(scr)


if __name__ == '__main__':
   if len(sys.argv) not in (3, 4):
      sys.exit(__doc__ or 'usage: make_logo.py badge.png out.scr [preview.png]')
   scr = make_logo(sys.argv[1])
   open(sys.argv[2], 'wb').write(scr)
   if len(sys.argv) == 4:
      sys.path.insert(0, __import__('os').path.dirname(__file__))
      from zxn_bootscreen import write_png
      write_png(sys.argv[3], scr)
