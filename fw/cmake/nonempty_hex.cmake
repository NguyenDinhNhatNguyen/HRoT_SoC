# Write one zero word into FILE if it is empty, so $readmemh and the FPGA tools never get an empty hex.
# Usage: cmake -DFILE=<hex> -P nonempty_hex.cmake
file(SIZE "${FILE}" hex_size)
if(hex_size EQUAL 0)
    file(WRITE "${FILE}" "00000000\n")
endif()
