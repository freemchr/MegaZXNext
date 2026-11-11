"""Judge out.txt of tb_zxn_sd: every output line (DE window) must show one input
line completely (columns 0..719, each once, in order), every input line on two
consecutive output lines, and every active input line (8..310) once per frame.
Prints a summary; exit 0 = pass."""
import sys
from collections import Counter

ACTIVE = 720
lines, cur = [], None
for rec in open(sys.argv[1]):
    p = rec.split()
    if p[0] == 'D':
        if p[2] == '1':
            cur = []
        elif cur is not None:
            lines.append(cur)
            cur = None
    elif p[0] == 'P' and cur is not None:
        try:
            v = int(p[2], 16)
            cur.append(((v >> 10) & 0x1FF, v & 0x3FF))
        except ValueError:                  # x / z
            cur.append((-1, -1))
lines = lines[1:]                       # the first window may be cut
bad = []
seq = []
for i, ln in enumerate(lines):
    srcs = {l for l, _ in ln}
    cols = [c for _, c in ln]
    if len(srcs) != 1 or cols != list(range(ACTIVE)):
        bad.append((i, len(ln), sorted(srcs)[:3], cols[:6], cols[-3:]))
    seq.append(ln[0][0] if ln else None)
# every input line twice in a row
pairs_ok = all(seq[i] == seq[i + 1] for i in range(0, len(seq) - 1, 2)) or \
           all(seq[i] == seq[i + 1] for i in range(1, len(seq) - 1, 2))
# one complete frame: the input lines between two line-8 starts
starts = [i for i in range(len(seq) - 1) if seq[i] == 8 and (i == 0 or seq[i - 1] != 8)]
frame = seq[starts[0]:starts[1]] if len(starts) >= 2 else []
cnt = Counter(frame)
twice = sum(1 for l in range(8, 311) if cnt.get(l) == 2)
frame_ok = twice == 303 and len(frame) == 606
print(f"output lines {len(lines)}, bad {len(bad)}, input lines seen {len(cnt)}, "
      f"of lines 8..310 twice in a frame {twice}/303, frame lines {len(frame)}, "
      f"consecutive pairs {pairs_ok}")
for b in bad[:4]:
    print("  bad line", b)
sys.exit(0 if not bad and pairs_ok and frame_ok else 1)
