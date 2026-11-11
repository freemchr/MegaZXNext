#!/usr/bin/env bash
# The analog Standard VGA path (M2M video_mixer, scandoubler on) with the ZX Next
# raster of main.vhd: 28 MHz clock, 14 MHz pixel enable. Runs the real
# video_mixer.sv/scandoubler.v/hq2x.sv/video_freezer.sv from M2M with Vivado xsim
# (Icarus Verilog would do too) and judges the output with check.py:
#   LINEDOUBLER = 1 (VGA_LINEDOUBLER in globals.vhd): must pass, every output line
#                   shows one complete input line, every input line twice
#   LINEDOUBLER = 0 (MiSTer's Hq2x, needs 4 clocks per pixel): red control, must
#                   fail (every second 14 MHz pixel dropped, GitHub issue #2)
# Needs Vivado 2026.1 (VIVADO_SETTINGS, default ~/Xilinx/2026.1/Vivado/settings64.sh).
# On Ubuntu 26.04 xsim needs libncurses.so.5: set LD_LIBRARY_PATH to a directory
# with a symlink to libncursesw.so.6 (AGENTS.md section 5).
# Usage: run.sh [workdir]   exit status 0 = pass
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
MIX="$HERE/../../../M2M/vhdl/controllers/MiSTer"
W="${1:-$(mktemp -d)}"
mkdir -p "$W" && cd "$W" || exit 2
# shellcheck disable=SC1090
source "${VIVADO_SETTINGS:-$HOME/Xilinx/2026.1/Vivado/settings64.sh}" > /dev/null 2>&1
xvlog -sv "$MIX/video_mixer.sv" "$MIX/scandoubler.v" "$MIX/hq2x.sv" "$MIX/video_freezer.sv" \
      "$HERE/gamma_stub.sv" "$HERE/tb_zxn_sd.sv" > xvlog.log 2>&1 || { grep ERROR xvlog.log; exit 2; }
fail=0
for ld in 1 0; do
   xelab -generic_top "LD=$ld" tb_zxn_sd -s "sim_ld$ld" -timescale 1ns/1ps > "xelab_ld$ld.log" 2>&1 \
      || { grep -i error "xelab_ld$ld.log"; exit 2; }
   xsim "sim_ld$ld" -R > "xsim_ld$ld.log" 2>&1 || { tail -3 "xsim_ld$ld.log"; exit 2; }
   mv out.txt "out_ld$ld.txt"
   python3 -I "$HERE/check.py" "out_ld$ld.txt" > "check_ld$ld.txt"
   rc=$?
   head -1 "check_ld$ld.txt"
   if [ "$ld" = 1 ] && [ $rc -ne 0 ]; then echo "FAIL: line doubler"; fail=1; fi
   if [ "$ld" = 1 ] && [ $rc -eq 0 ]; then echo "PASS: line doubler (LINEDOUBLER = 1)"; fi
   if [ "$ld" = 0 ] && grep -q "\[1, 1, 3, 3, 5, 5\]" "check_ld$ld.txt"; then
      echo "PASS: red control (Hq2x drops every second pixel)"
   elif [ "$ld" = 0 ]; then echo "FAIL: red control did not show the decimation"; fail=1; fi
done
echo "work directory: $W"
exit $fail
