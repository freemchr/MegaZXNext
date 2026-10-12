#!/usr/bin/env bash
#
# ZX Spectrum Next for MEGA65 (MegaZXNext)
#
# Tests ZXN_MOUNT (../zxn_mount.asm) in the QNICE emulator with FAT32 disk images:
#   1. contiguous /zxnext/boot.img behind a filler file, placed so that adding the cluster
#      offset to the first data sector carries from the low into the high word (checked)
#   2. fragmented /zxnext/boot.img (one cluster of the chain moved to the end of the disk): 3 extents
#   2b. more than 512 extents: refused
#   3. contiguous /zxnext/boot.vhd only
#   4. no image
# The expected first sector and size are computed independently from the image (python).
#
# Needs: gcc, mtools, mkfs.fat (dosfstools), sfdisk, python3. Run from this directory.
#
# MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3

set -euo pipefail

QNICE=../../../M2M/QNICE
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
export MTOOLS_SKIP_CHECK=1

# Emulator: build a private copy (keeps the M2M submodule clean); -fcommon for current gcc
mkdir -p "$WORK/qnice/tools"
cp -r "$QNICE/emulator" "$QNICE/dist_kit" "$WORK/qnice/"
cp "$QNICE/tools/detect.include" "$WORK/qnice/tools/"
( cd "$WORK/qnice/emulator" && sed -i 's/-O3 /-O3 -fcommon /' make.bash && bash make.bash > /dev/null 2>&1 )
EMU=$WORK/qnice/emulator/qnice

"$QNICE/assembler/asm" test_zxn_mount.asm > /dev/null

# FAT32 image: MBR, partition at sector 2048, 4 KB clusters
make_image() {
    local img=$1
    truncate -s 128M "$img"
    echo "start=2048, type=c" | sfdisk --quiet --label dos "$img"
    mkfs.fat -F 32 -s 8 -h 2048 --offset 2048 "$img" $(( (128 * 2048 - 2048) / 2 )) > /dev/null
    mmd -i "$img@@1048576" ::/zxnext
}
pattern() { head -c "$1" /dev/urandom > "$2"; }

# Expected result: first sector and size of the image, or "FRAG" / "NONE"
expect() {
    python3 -I - "$1" "$2" << 'EOF'
import struct, sys
img, name = sys.argv[1], sys.argv[2].upper()
f = open(img, 'rb'); base = 2048 * 512
f.seek(base); bs = f.read(512)
bps, spc, rsv, nf = struct.unpack_from('<HBHB', bs, 11)
spf = struct.unpack_from('<I', bs, 36)[0]; root = struct.unpack_from('<I', bs, 44)[0]
fat_lba = 2048 + rsv; clus_lba = fat_lba + nf * spf
def nxt(c):
    f.seek(fat_lba * 512 + c * 4); return struct.unpack('<I', f.read(4))[0] & 0x0FFFFFFF
def find(c, want):
    while 2 <= c < 0x0FFFFFF8:
        f.seek((clus_lba + (c - 2) * spc) * 512); d = f.read(spc * 512)
        for i in range(0, len(d), 32):
            e = d[i:i + 32]
            if e[0] == 0: return None
            n = e[:8].decode('latin1').strip() + ('.' + e[8:11].decode('latin1').strip() if e[8:11].strip() else '')
            if e[11] != 0x0F and e[0] != 0xE5 and n == want:
                return (struct.unpack_from('<H', e, 20)[0] << 16 | struct.unpack_from('<H', e, 26)[0],
                        struct.unpack_from('<I', e, 28)[0])
        c = nxt(c)
d = find(root, 'ZXNEXT')
r = find(d[0], name) if d else None
if not r: print('NONE'); sys.exit()
c, size = r
n = -(-size // (spc * 512))
ext, k = [(0, c)], 0
while k < n - 1:
    e = nxt(c)
    if e != c + 1: ext.append(((k + 1) * spc, e))
    c, k = e, k + 1
if len(ext) > 512: print('MANY'); sys.exit()
for v, cl in ext:
    print('EXT: %08X %08X' % (v, clus_lba + (cl - 2) * spc))
sec = size // 512
print('REGS: %04X %04X 0001 0001 0000 %04X' % (sec & 0xFFFF, sec >> 16, len(ext)))
first = clus_lba + (r[0] - 2) * spc
carry = ((r[0] - 2) * spc & 0xFFFF) + (clus_lba & 0xFFFF) > 0xFFFF
print('CARRY' if carry else 'NOCARRY')
EOF
}

run() {
    printf 'LOAD %s\nATTACH %s\nLOAD test_zxn_mount.out\nRUN 8000\nQUIT\n' \
        "$QNICE/monitor/monitor.out" "$1" | "$EMU" 2>&1 | tr -d '\r'
}

fail=0
check() {
    local title=$1 img=$2 name=$3 out exp
    out=$(run "$img")
    exp=$(expect "$img" "$name")
    case $exp in
        NONE) grep -q "RESULT: ZX Next SD card image not found" <<< "$out" ;;
        MANY) grep -q "RESULT: The ZX Next SD card image is in more" <<< "$out" ;;
        *)    grep -q "RESULT: 0000" <<< "$out" &&
              [ "$(grep -E '^(EXT|REGS):' <<< "$out" | sed 's/ *$//')" = "$(grep -E '^(EXT|REGS):' <<< "$exp")" ] ;;
    esac && echo "PASS  $title ($(grep -c '^EXT' <<< "$exp") extents, $(tail -1 <<< "$exp"))" ||
        { echo "FAIL  $title"; echo "expected:"; echo "$exp"; echo "got:"; echo "$out" | grep -E "ZX Next|RESULT|REGS|CODE|EXT"; fail=1; }
}

# 1. contiguous boot.img behind a filler of 7930 clusters: the image starts around cluster 7934,
#    (7934 - 2) * 8 = 0xF7E0 plus the first data sector (about 0x0A30) carries
make_image "$WORK/t1.img"
pattern $((7930 * 4096)) "$WORK/filler"; pattern 16M "$WORK/boot.img"
mcopy -i "$WORK/t1.img@@1048576" "$WORK/filler" ::/filler
mcopy -i "$WORK/t1.img@@1048576" "$WORK/boot.img" ::/zxnext/boot.img
expect "$WORK/t1.img" boot.img | grep -q "^CARRY$" || { echo "FAIL  test 1 does not need a carry"; exit 1; }
check "contiguous boot.img (carry)" "$WORK/t1.img" boot.img

# 2. fragmented: cluster 300 of a 4 MB image is moved to a free cluster near the end of the disk
#    (both FAT copies; the data is not moved, only the chain matters here)
make_image "$WORK/t2.img"
pattern 4M "$WORK/boot.img"
mcopy -i "$WORK/t2.img@@1048576" "$WORK/boot.img" ::/zxnext/boot.img
python3 -I - "$WORK/t2.img" << 'EOF'
import struct, sys
f = open(sys.argv[1], 'r+b'); base = 2048 * 512
f.seek(base); bs = f.read(512)
bps, spc, rsv, nf = struct.unpack_from('<HBHB', bs, 11)
spf = struct.unpack_from('<I', bs, 36)[0]
def setfat(c, v):
    for k in range(nf):
        f.seek(base + (rsv + k * spf) * bps + c * 4); f.write(struct.pack('<I', v))
def getfat(c):
    f.seek(base + rsv * bps + c * 4); return struct.unpack('<I', f.read(4))[0] & 0x0FFFFFFF
c = 2
while getfat(c) != 0: c += 1                      # first free cluster: behind the image
start = c - 1024                                  # 4 MB = 1024 clusters
assert getfat(start + 1023) >= 0x0FFFFFF8 and getfat(start) == start + 1
far = spf * bps // 4 - 10                         # a free cluster near the end
setfat(start + 299, far); setfat(far, start + 301); setfat(start + 300, 0)
EOF
check "fragmented boot.img" "$WORK/t2.img" boot.img

# 2b. more than 512 extents: 600 clusters chained as c, c+2, c+4, ..., c+1, c+3, ...
make_image "$WORK/t5.img"
pattern $((600 * 4096)) "$WORK/boot.img"
mcopy -i "$WORK/t5.img@@1048576" "$WORK/boot.img" ::/zxnext/boot.img
python3 -I - "$WORK/t5.img" << 'EOF'
import struct, sys
f = open(sys.argv[1], 'r+b'); base = 2048 * 512
f.seek(base); bs = f.read(512)
bps, spc, rsv, nf = struct.unpack_from('<HBHB', bs, 11)
spf = struct.unpack_from('<I', bs, 36)[0]
def setfat(c, v):
    for k in range(nf):
        f.seek(base + (rsv + k * spf) * bps + c * 4); f.write(struct.pack('<I', v))
def getfat(c):
    f.seek(base + rsv * bps + c * 4); return struct.unpack('<I', f.read(4))[0] & 0x0FFFFFFF
c = 2
while getfat(c) != 0: c += 1
start = c - 600
order = [start + i for i in range(0, 600, 2)] + [start + i for i in range(1, 600, 2)]
for a, b in zip(order, order[1:]): setfat(a, b)
setfat(order[-1], 0x0FFFFFFF)
EOF
check "more than 512 extents" "$WORK/t5.img" boot.img

# 3. boot.vhd only
make_image "$WORK/t3.img"
pattern 8M "$WORK/boot.vhd"
mcopy -i "$WORK/t3.img@@1048576" "$WORK/boot.vhd" ::/zxnext/boot.vhd
check "boot.vhd" "$WORK/t3.img" boot.vhd

# 4. no image
make_image "$WORK/t4.img"
check "no image" "$WORK/t4.img" boot.img

exit $fail
