#!/bin/bash
# Virtual Platform secure boot (SystemC/TLM-2.0), chay trong WSL tu thu muc sim/:
#   bash run_vp.sh [app.hex]
# Build: vp/src/*.cpp + HAL that cua firmware (fw/hal, che do HAL_HOST_MODEL) + SHA-256 tham chieu.
# Chay 2 kich ban: image dung (App duoc nha reset) va image bi sua (--tamper, App bi giu reset).
set -e
SYSTEMC_HOME="${SYSTEMC_HOME:-/usr/local/systemc-2.3.3}"
B=../vp/build
mkdir -p "$B"

gcc -std=c11 -O1 -Wall -DHAL_HOST_MODEL -I../fw/hal -I../fw/hal/test -c ../fw/hal/sha256_hal.c      -o "$B/sha256_hal.o"
gcc -std=c11 -O1 -Wall                  -I../fw/hal/test             -c ../fw/hal/test/sha256_ref.c -o "$B/sha256_ref.o"
g++ -std=c++17 -O1 -Wall -Wno-overloaded-virtual -DHAL_HOST_MODEL -I"$SYSTEMC_HOME/include" -I../fw/hal -I../fw/hal/test \
    ../vp/src/*.cpp "$B/sha256_hal.o" "$B/sha256_ref.o" \
    -L"$SYSTEMC_HOME/lib-linux64" -lsystemc -lm -o "$B/vp_sim"

APP_HEX="${1:-$B/app.hex}"
[ -f "$APP_HEX" ] || python3 ../dv/tests/mkhex.py "$B"

export LD_LIBRARY_PATH="$SYSTEMC_HOME/lib-linux64:$LD_LIBRARY_PATH"
export SC_COPYRIGHT_MESSAGE=DISABLE
echo "===== Kich ban 1: image dung ====="
"$B/vp_sim" "$APP_HEX"
echo "===== Kich ban 2: image bi sua ====="
"$B/vp_sim" "$APP_HEX" --tamper
