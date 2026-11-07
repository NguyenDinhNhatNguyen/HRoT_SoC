# Build kv260-hrot.bit.bin and kv260-hrot.dtbo on the PC with the bootgen and dtc that come with Vitis,
# so the board needs no internet and no apt install. Run in PowerShell from this folder after
# `make kv260` (copies ..\build\kv260.bit here). Then copy kv260-hrot.bit.bin, kv260-hrot.dtbo,
# shell.json and install_on_board.sh to the board and run install_on_board.sh there.
param([string]$Vitis = "D:\AMDDesignTools\2025.2\Vitis")
$ErrorActionPreference = "Stop"
$name = "kv260-hrot"
Set-Location $PSScriptRoot
Copy-Item ..\build\kv260.bit "$name.bit" -Force
(Get-Content template.bif -Raw) -replace '@BIT@', "$name.bit" | Set-Content -Encoding ascii "$name.bif"
& "$Vitis\bin\bootgen.bat" -image "$name.bif" -arch zynqmp -o "$name.bit.bin" -w
& "$Vitis\bin\dtc.exe" -I dts -O dtb -o "$name.dtbo" "$name.dtsi"
Get-ChildItem "$name.bit.bin", "$name.dtbo" | Select-Object Name, Length
