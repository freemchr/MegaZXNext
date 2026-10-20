#!/usr/bin/env python3
# MegaZXNext: puts the MegaZXNext logo on the boot screen of the ZX Next firmware (TBBLUE.FW).
#
# The firmware picks its boot screen by the machine ID: the core reports 0xDA ("MiSTer"), so it
# shows the "MiSTer Next" picture. This tool replaces the logo part (character rows 0..9) of
# that picture in a copy of TBBLUE.FW and keeps the rest of it. It never changes the input file.
#
#   zxn_bootscreen.py patch TBBLUE.FW OUT.FW [--logo megazxnext.scr] [--screen 6]
#   zxn_bootscreen.py show  TBBLUE.FW DIR          (all boot screens as PNG)
#
# How the firmware stores the screens (next-firmware, boot.c and vdplow.s, GPL v3): the 512 byte
# map at the start of TBBLUE.FW gives the first block of the screens (block 8). They start with a
# 227 byte palette and a 49152 byte Layer 2 picture; then come 8 boot screens of 8896 bytes,
# picked by s[machine ID >> 4]. Each is the marker 55 AA 5A A5 and 988 groups of 9 bytes; the
# firmware turns each group into 7 bytes of a ULA screen (_vdp_reveal), written downwards from
# 0x5AFF (988 * 7 = 6916 bytes: the 6912 byte screen and 4 bytes below it). The transformation
# only moves and XORs bits, i.e. it is linear over GF(2), so it is inverted by solving one 56x72
# bit system. Python 3 standard library only.
#
# done by Chris Freeman in 2026 and licensed under GPL v3

import os
import struct
import sys
import zlib

FW_BLK_SCREENS = 8
PALETTE_SIZE   = 227
LAYER2_SIZE    = 49152
SCREEN_SIZE    = 8896
NUM_SCREENS    = 8
MARKER         = bytes([0x55, 0xAA, 0x5A, 0xA5])
GROUPS         = 988
MISTER_SCREEN  = 6                  # s[0xDA >> 4] in boot.c
LOGO_ROWS      = 10                 # character rows taken from the logo


def reveal(data):
   """Decode one stored screen (8896 bytes) as _vdp_reveal does. Returns 6916 bytes for
   addresses 0x3FFC..0x5AFF."""
   assert data[:4] == MARKER, 'boot screen marker missing'
   mem = bytearray(data) + bytes(16)
   out = bytearray(GROUPS * 7)
   sp, de = 4, len(out) - 1
   for _ in range(GROUPS):
      sp, de = _z80_group(mem, sp, out, de)
   return bytes(out)


# The loop body of _vdp_reveal as a list of instructions, interpreted below. This is a direct
# transcription of vdplow.s (next-firmware), so it can be compared line by line.
_LOOP = """pop hl|dec sp|ld a,l|ld i,a|pop hl|push hl|xor l|rl h|rl h|adc a,a|st
pop hl|ld a,i|xor h|pop hl|push hl|rl l|rl l|adc a,a|rl l|adc a,a|st
pop hl|push hl|ld a,i|xor l|rl h|rl h|adc a,a|rl h|adc a,a|rl h|adc a,a|st
pop hl|ld a,i|xor h|pop hl|push hl|rl l|rl l|adc a,a|rl l|adc a,a|rl l|adc a,a|rl l|adc a,a|st
pop hl|push hl|ld a,i|xor l|rl h|rl h|adc a,a|rl h|adc a,a|rl h|adc a,a|rl h|adc a,a|rl h|adc a,a|st
pop hl|ld a,i|xor h|pop hl|push hl|rl l|rl l|adc a,a|rl l|adc a,a|rl l|adc a,a|rl l|adc a,a|rl l|adc a,a|rl l|adc a,a|st
pop hl|ld a,i|xor h|add a,a|rr l|rra|st""".replace('\n', '|').split('|')


def _z80_group(mem, sp, out, de):
   r = {'a': 0, 'h': 0, 'l': 0, 'i': 0, 'c': 0}
   for op in _LOOP:
      if op == 'pop hl':
         r['l'], r['h'] = mem[sp], mem[sp + 1]
         sp += 2
      elif op == 'push hl':
         sp -= 2
         mem[sp], mem[sp + 1] = r['l'], r['h']
      elif op == 'dec sp':
         sp -= 1
      elif op == 'ld a,l':
         r['a'] = r['l']
      elif op == 'ld i,a':
         r['i'] = r['a']
      elif op == 'ld a,i':
         r['a'] = r['i']
      elif op.startswith('xor '):
         r['a'] ^= r[op[4]]
         r['c'] = 0
      elif op.startswith('rl '):
         v = r[op[3]] << 1 | r['c']
         r[op[3]], r['c'] = v & 255, v >> 8
      elif op == 'adc a,a':
         v = r['a'] * 2 + r['c']
         r['a'], r['c'] = v & 255, v >> 8
      elif op == 'add a,a':
         v = r['a'] * 2
         r['a'], r['c'] = v & 255, v >> 8
      elif op == 'rr l':
         v = r['l']
         r['l'], r['c'] = v >> 1 | r['c'] << 7, v & 1
      elif op == 'rra':
         v = r['a']
         r['a'], r['c'] = v >> 1 | r['c'] << 7, v & 1
      elif op == 'st':
         out[de] = r['a']
         de -= 1
      else:
         raise ValueError(op)
   return sp, de


def _group_out(g):
   """7 output bytes (as one 56 bit number, first written byte = highest) of one 9 byte group."""
   mem = bytearray(g) + bytes(4)
   out = bytearray(7)
   _z80_group(mem, 0, out, 6)
   return int.from_bytes(out, 'big')


def _solver():
   """For each of the 56 output bits of a group, a 9 byte input that produces only that bit."""
   assert _group_out(bytes(9)) == 0
   basis = {}                       # pivot bit -> (output, input), fully reduced
   for j in range(72):
      v, src = _group_out((1 << j).to_bytes(9, 'big')), 1 << j
      for p, (bv, bs) in basis.items():
         if v >> p & 1:
            v, src = v ^ bv, src ^ bs
      if v:
         p = v.bit_length() - 1
         for q, (bv, bs) in list(basis.items()):
            if bv >> p & 1:
               basis[q] = (bv ^ v, bs ^ src)
         basis[p] = (v, src)
   assert len(basis) == 56, 'group transformation is not invertible'
   # 56 pivots in 56 bits, fully reduced: every output is a single bit.
   return [basis[p][1] for p in range(56)]


def hide(screen6916, original):
   """Inverse of reveal(): 6916 bytes (0x3FFC..0x5AFF) -> 8896 stored bytes. Each group of 9
   bytes has 16 bits that the firmware ignores; they are taken from the original, so groups
   whose output does not change stay as they are."""
   inv = _solver()
   data = bytearray(MARKER)
   top = len(screen6916) - 1
   for k in range(GROUPS):
      chunk = screen6916[top - 7 * k - 6:top - 7 * k + 1]       # written downwards
      orig = original[4 + 9 * k:13 + 9 * k]
      diff = int.from_bytes(chunk, 'big') ^ _group_out(orig)
      g = int.from_bytes(orig, 'big')
      for bit in range(56):
         if diff >> bit & 1:
            g ^= inv[bit]
      data += g.to_bytes(9, 'big')
   assert reveal(bytes(data)) == bytes(screen6916)
   return bytes(data)


def screens_offset(fw):
   start = 1 + fw[FW_BLK_SCREENS * 4] + 256 * fw[FW_BLK_SCREENS * 4 + 1]
   base = start * 512 + PALETTE_SIZE + LAYER2_SIZE
   for k in range(NUM_SCREENS):
      if fw[base + k * SCREEN_SIZE:base + k * SCREEN_SIZE + 4] != MARKER:
         sys.exit(f'TBBLUE.FW: boot screen {k} not found where expected (unknown firmware layout)')
   return base


def scr_rows_merge(old, logo):
   """old screen with character rows 0..LOGO_ROWS-1 (pixels and attributes) from logo."""
   new = bytearray(old)
   for y in range(LOGO_ROWS * 8):
      addr = ((y & 0xc0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2)
      new[addr:addr + 32] = logo[addr:addr + 32]
   new[6144:6144 + LOGO_ROWS * 32] = logo[6144:6144 + LOGO_ROWS * 32]
   return bytes(new)


def write_png(name, scr):
   pal = [(0, 0, 0), (0, 0, 0xd7), (0xd7, 0, 0), (0xd7, 0, 0xd7),
          (0, 0xd7, 0), (0, 0xd7, 0xd7), (0xd7, 0xd7, 0), (0xd7, 0xd7, 0xd7)]
   palb = [(0, 0, 0), (0, 0, 255), (255, 0, 0), (255, 0, 255),
           (0, 255, 0), (0, 255, 255), (255, 255, 0), (255, 255, 255)]
   raw = bytearray()
   for y in range(192):
      raw.append(0)
      for xb in range(32):
         byte = scr[((y & 0xc0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | xb]
         att = scr[6144 + (y // 8) * 32 + xb]
         p = palb if att & 0x40 else pal
         for b in range(8):
            raw += bytes(p[att & 7] if byte & (0x80 >> b) else p[(att >> 3) & 7])

   def chunk(t, b):
      return struct.pack('>I', len(b)) + t + b + struct.pack('>I', zlib.crc32(t + b) & 0xffffffff)
   open(name, 'wb').write(b'\x89PNG\r\n\x1a\n'
                          + chunk(b'IHDR', struct.pack('>IIBBBBB', 256, 192, 8, 2, 0, 0, 0))
                          + chunk(b'IDAT', zlib.compress(bytes(raw))) + chunk(b'IEND', b''))


def main(argv):
   args = argv[1:]
   opts = {'--logo': os.path.join(os.path.dirname(os.path.abspath(__file__)), 'megazxnext.scr'),
           '--screen': str(MISTER_SCREEN)}
   for o in list(opts):
      if o in args:
         i = args.index(o)
         opts[o] = args[i + 1]
         del args[i:i + 2]
   if len(args) != 3 or args[0] not in ('patch', 'show'):
      sys.exit('usage: zxn_bootscreen.py patch TBBLUE.FW OUT.FW [--logo FILE.scr] [--screen N]\n'
               '       zxn_bootscreen.py show  TBBLUE.FW DIR')
   cmd, src, dst = args
   fw = bytearray(open(src, 'rb').read())
   base = screens_offset(fw)

   if cmd == 'show':
      os.makedirs(dst, exist_ok=True)
      for k in range(NUM_SCREENS):
         scr = reveal(fw[base + k * SCREEN_SIZE:base + (k + 1) * SCREEN_SIZE])[4:]
         write_png(os.path.join(dst, f'screen{k}.png'), scr)
      print(f'{NUM_SCREENS} boot screens written to {dst}')
      return

   if os.path.abspath(src) == os.path.abspath(dst):
      sys.exit('refusing to overwrite the input file: write to a new file')
   k = int(opts['--screen'])
   logo = open(opts['--logo'], 'rb').read()
   assert len(logo) == 6912, 'the logo must be a 6912 byte .scr file'
   off = base + k * SCREEN_SIZE
   old = reveal(fw[off:off + SCREEN_SIZE])
   new = old[:4] + scr_rows_merge(old[4:], logo)       # keep the 4 bytes below 0x4000
   fw[off:off + SCREEN_SIZE] = hide(new, fw[off:off + SCREEN_SIZE])
   open(dst, 'wb').write(fw)
   print(f'boot screen {k} replaced: {dst}')


if __name__ == '__main__':
   main(sys.argv)
