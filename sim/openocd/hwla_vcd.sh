#!/bin/bash
#-----------------------------------------------------------------------------
# Title      : Hook of the OpenOCD co-simulation of the HWLA captures
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : hwla_vcd.sh
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Hook of sim_*_openocd_hwla (cwd = work root) :
#                vcd <args> : post_run, hwla/hwla2vcd.py (copied to hwla/ by
#                       asylum:debug:HWLA >= 3.1.0) rebuilds hwla.vcd from
#                       hwla.bin (written by picosoc_hwla_dump in
#                       hwla_check.cfg) with the argument file <args>
#                       (tools/hwla/*.args copied to hwla/ : configuration of
#                       the HWLA, named signals of the probes) : one complete
#                       capture, its trigger wire and the named signals.
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-27  1.0      mrosiere Created
# 2026-11-27  1.1      mrosiere Renamed (was hwla_tools.sh) : copy removed,
#                               jtag_axis.tcl is in tools/openocd
#-----------------------------------------------------------------------------

set -e

case $1 in
    vcd)
        python3 hwla/hwla2vcd.py hwla.bin --args-file "$2" -o hwla.vcd
        for name in trigger dcs daddr drdata ics iaddr idata; do
            grep -q "^\$var wire [0-9]* [^ ]* $name " hwla.vcd || { echo "hwla_vcd.sh : no signal $name in hwla.vcd"; exit 1; }
        done
        echo "hwla_vcd.sh : hwla.bin decoded by hwla/hwla2vcd.py : hwla.vcd" ;;
    *)
        echo "Usage : $0 vcd <args file>"
        exit 1 ;;
esac
