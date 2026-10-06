#!/bin/bash
SYSTEMC_HOME="/usr/local/systemc-2.3.3"

g++ -I$SYSTEMC_HOME/include -L$SYSTEMC_HOME/lib-linux64 \
    ../vp/src/*.cpp -lsystemc -lm -o ../vp/build/vp_sim

export LD_LIBRARY_PATH=$SYSTEMC_HOME/lib-linux64:$LD_LIBRARY_PATH
../vp/build/vp_sim