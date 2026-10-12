#!/usr/bin/env bash
#
# ZX Spectrum Next for MEGA65 (MegaZXNext)
#
# Builds the ZX Next's SD card image from an official System/Next distribution, e.g.
#     https://www.specnext.com/distro/24.11/sn-complete-24.11.zip
# The image is what the ZX Next sees as its SD card. Copy it to the MEGA65's SD card as
#     /zxnext/boot.img
#
# Usage: tools/make-sd-image.sh <distribution.zip> <boot.img> [size in MiB, default 2048]
#
# The image is a raw SD card: an MBR with one FAT32 partition (type 0x0C) starting at sector 2048.
# The distribution is copied unchanged and in the order its README asks for (QXL.WIN first, so
# that it is contiguous for the QL core). Afterwards every file is compared with the zip.
#
# Needs: unzip, sfdisk (util-linux), mkfs.fat (dosfstools), mcopy/mmd/mdir (mtools), python3.
#
# MEGA65 port done by Chris Freeman in 2026 and licensed under GPL v3

set -euo pipefail

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
    echo "Usage: $0 <distribution.zip> <boot.img> [size in MiB, default 2048]" >&2
    exit 1
fi

ZIP=$(realpath "$1")
IMG=$(realpath -m "$2")
SIZE_MB=${3:-2048}
PART_START=2048                                   # sectors

for tool in unzip sfdisk mkfs.fat mcopy mmd mdir python3; do
    command -v "$tool" > /dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
if [ -e "$IMG" ]; then
    echo "$IMG exists: not overwriting it" >&2
    exit 1
fi
if [ "$SIZE_MB" -lt 256 ]; then
    echo "Size must be at least 256 MiB (FAT32)" >&2
    exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "Unpacking $(basename "$ZIP")"
unzip -q "$ZIP" -d "$WORK/dist"

echo "Creating a ${SIZE_MB} MiB image"
truncate -s "${SIZE_MB}M" "$IMG"
echo "start=$PART_START, type=c" | sfdisk --quiet --label dos "$IMG"
# Hidden sectors = partition start, as on a card formatted in a PC; size in 1 KiB blocks
mkfs.fat -F 32 -n ZXNEXT --offset "$PART_START" -h "$PART_START" "$IMG" \
    $(( (SIZE_MB * 1024 * 1024 / 512 - PART_START) / 2 )) > /dev/null

export MTOOLS_SKIP_CHECK=1
export MTOOLS_NO_VFAT=0
PART="$IMG@@$((PART_START * 512))"

echo "Copying the distribution"
cd "$WORK/dist"
# QXL.WIN first (see the distribution's README), then everything else in a stable order
if [ -f QXL.WIN ]; then
    mcopy -i "$PART" -m QXL.WIN ::/
fi
find . -mindepth 1 -type d | LC_ALL=C sort | while read -r d; do
    mmd -i "$PART" "::/${d#./}"
done
find . -type f ! -path ./QXL.WIN | LC_ALL=C sort | while read -r f; do
    mcopy -i "$PART" -m "$f" "::/${f#./}"
done
cd - > /dev/null

echo "Checking every file against the zip"
python3 -I - "$IMG" "$ZIP" "$PART_START" << 'EOF'
import struct, sys, zipfile, zlib

img, zp, part = sys.argv[1], sys.argv[2], int(sys.argv[3])
f = open(img, 'rb')
base = part * 512
f.seek(base)
bs = f.read(512)
bps, spc, rsv, nf = struct.unpack_from('<HBHB', bs, 11)
spf = struct.unpack_from('<I', bs, 36)[0]
root = struct.unpack_from('<I', bs, 44)[0]
fat = base + rsv * bps
data = base + (rsv + nf * spf) * bps
csz = spc * bps

def chain(c):
    while 2 <= c < 0x0FFFFFF8:
        yield c
        f.seek(fat + c * 4)
        c = struct.unpack('<I', f.read(4))[0] & 0x0FFFFFFF

def read(c, size=None):
    out = bytearray()
    for cl in chain(c):
        f.seek(data + (cl - 2) * csz)
        out += f.read(csz)
    return bytes(out if size is None else out[:size])

files = {}
def walk(c, path):
    d, lfn = read(c), []
    for i in range(0, len(d), 32):
        e = d[i:i + 32]
        if e[0] == 0:
            break
        if e[0] == 0xE5:
            lfn = []
            continue
        if e[11] == 0x0F:
            lfn.insert(0, (e[1:11] + e[14:26] + e[28:32]).decode('utf-16le').split('\x00')[0])
            continue
        if lfn:
            name = ''.join(lfn)
        else:
            # short name; NT case flags: bit 3 = lower case name, bit 4 = lower case extension
            name = e[:8].decode('latin1').rstrip()
            if e[12] & 0x08:
                name = name.lower()
            if e[8:11].strip():
                ext = e[8:11].decode('latin1').rstrip()
                name += '.' + (ext.lower() if e[12] & 0x10 else ext)
        lfn = []
        if e[11] & 0x08 or name in ('.', '..'):
            continue
        cl = (struct.unpack_from('<H', e, 20)[0] << 16) | struct.unpack_from('<H', e, 26)[0]
        if e[11] & 0x10:
            walk(cl, path + name + '/')
        else:
            files[path + name] = (cl, struct.unpack_from('<I', e, 28)[0])

walk(root, '')
bad = 0
z = zipfile.ZipFile(zp)
expected = [i for i in z.infolist() if not i.is_dir()]
for i in expected:
    if i.filename not in files:
        print('missing:', i.filename)
        bad += 1
        continue
    cl, size = files[i.filename]
    if size != i.file_size or zlib.crc32(read(cl, size) if size else b'') != i.CRC:
        print('differs:', i.filename)
        bad += 1
extra = set(files) - {i.filename for i in expected}
for name in sorted(extra):
    print('extra:', name)
    bad += 1
if bad:
    sys.exit('%d problems' % bad)
print('%d files identical to the distribution' % len(expected))
EOF

echo "Done: $IMG. Copy it to the MEGA65 SD card as /zxnext/boot.img"
