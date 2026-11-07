#!/bin/bash
# Run on the KV260 (Kria Ubuntu) after copying kv260.bit into this folder.
# Needs: sudo apt install bootgen-xlnx device-tree-compiler
# Follows AMD's flow (Xilinx/kria-apps-firmware): .bit to .bit.bin with bootgen, .dtsi to .dtbo with dtc,
# then the three files go to /lib/firmware/xilinx/<name>/ and xmutil loads them
set -e
NAME=kv260-hrot
cd "$(dirname "$0")"
# Skip the conversion when make_on_pc.ps1 already made $NAME.bit.bin and $NAME.dtbo on the PC
if [ ! -f $NAME.bit.bin ] || [ ! -f $NAME.dtbo ]; then
    [ -f kv260.bit ] || { echo "copy kv260.bit (fpga/xilinx/kv260/build) into this folder first"; exit 1; }
    cp kv260.bit $NAME.bit
    sed "s#@BIT@#$NAME.bit#" template.bif > $NAME.bif
    bootgen -image $NAME.bif -arch zynqmp -o $NAME.bit.bin -w
    dtc -I dts -O dtb -o $NAME.dtbo $NAME.dtsi
fi
sudo mkdir -p /lib/firmware/xilinx/$NAME
sudo cp $NAME.bit.bin $NAME.dtbo shell.json /lib/firmware/xilinx/$NAME/
sudo xmutil unloadapp || true
sudo xmutil loadapp $NAME
