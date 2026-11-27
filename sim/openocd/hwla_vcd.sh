#!/bin/bash
#-----------------------------------------------------------------------------
# Title      : Hook of the OpenOCD co-simulation of the HWLA captures
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : hwla_vcd.sh
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Hook of sim_*_openocd_hwla (cwd = work root) :
#                vcd <args> [options] : post_run, hwla/hwla2vcd.py (copied to hwla/ by
#                       asylum:debug:HWLA >= 3.1.0) rebuilds hwla.vcd from
#                       hwla.bin (written by picosoc_hwla_dump in
#                       hwla_check.cfg) with the argument file <args>
#                       (tools/hwla/*.args copied to hwla/ : configuration of
#                       the HWLA, named signals of the probes) : one complete
#                       capture, its trigger wire and the named signals
#                       (diff included) ; [options] after the file override
#                       it (e.g. -d 64 -p 32 : the HWLA_* generics of the
#                       co-simulation, the file has those of the boards).
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-27  1.0      mrosiere Created
# 2026-11-27  1.1      mrosiere Renamed (was hwla_tools.sh) : copy removed,
#                               jtag_axis.tcl is in tools/openocd
# 2026-11-27  1.2      mrosiere Options after the argument file ; signal diff
#-----------------------------------------------------------------------------

set -e

case $1 in
    vcd)
        args=$2; shift 2
        python3 hwla/hwla2vcd.py hwla.bin --args-file "$args" "$@" -o hwla.vcd
        for name in trigger dcs daddr drdata ics iaddr idata diff; do
            grep -q "^\$var wire [0-9]* [^ ]* $name " hwla.vcd || { echo "hwla_vcd.sh : no signal $name in hwla.vcd"; exit 1; }
        done
        echo "hwla_vcd.sh : hwla.bin decoded by hwla/hwla2vcd.py : hwla.vcd" ;;
    *)
        echo "Usage : $0 vcd <args file> [hwla2vcd.py options]"
        exit 1 ;;
esac
