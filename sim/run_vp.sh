#!/bin/bash
# Secure boot on the SystemC/TLM-2.0 virtual platform. Run in WSL from sim/:
#   bash run_vp.sh [app.hex]
# Builds vp/src/*.cpp together with the firmware's real HAL (fw/hal, HAL_HOST_MODEL) and the
# reference SHA-256, then runs two cases: a good image (App released) and a tampered one
# (--tamper, App kept in reset).
set -e
SYSTEMC_HOME="${SYSTEMC_HOME:-/usr/local/systemc-2.3.3}"
# 2.3.3 builds install into lib-linux64, 2.3.4 into lib
SC_LIB="$SYSTEMC_HOME/lib-linux64"
[ -d "$SC_LIB" ] || SC_LIB="$SYSTEMC_HOME/lib"
B=../vp/build
mkdir -p "$B"

gcc -std=c11 -O1 -Wall -DHAL_HOST_MODEL -I../fw/hal -I../fw/hal/test -c ../fw/hal/sha256_hal.c      -o "$B/sha256_hal.o"
gcc -std=c11 -O1 -Wall                  -I../fw/hal/test             -c ../fw/hal/test/sha256_ref.c -o "$B/sha256_ref.o"
g++ -std=c++17 -O1 -Wall -Wno-overloaded-virtual -DHAL_HOST_MODEL -I"$SYSTEMC_HOME/include" -I../fw/hal -I../fw/hal/test \
    ../vp/src/*.cpp "$B/sha256_hal.o" "$B/sha256_ref.o" \
    -L"$SC_LIB" -lsystemc -lm -o "$B/vp_sim"

APP_HEX="${1:-$B/app.hex}"
[ -f "$APP_HEX" ] || python3 ../dv/sw/mkhex.py "$B"

export LD_LIBRARY_PATH="$SC_LIB:$LD_LIBRARY_PATH"
export SC_COPYRIGHT_MESSAGE=DISABLE
echo "===== Case 1: good image ====="
"$B/vp_sim" "$APP_HEX"
echo "===== Case 2: tampered image ====="
"$B/vp_sim" "$APP_HEX" --tamper
