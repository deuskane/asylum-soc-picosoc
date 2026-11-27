#!/bin/bash
#-----------------------------------------------------------------------------
# Title      : Hooks of the OpenOCD co-simulation of the HWLA captures
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : hwla_tools.sh
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Hooks of sim_*_openocd_hwla (cwd = work root) :
#                copy : pre_build, the tools of two dependencies, taken from
#                       their cores (no copy of them in this repository) :
#                       tools/openocd/jtag_axis.tcl of asylum:debug:jtag to
#                       openocd/ (sourced by picosoc.cfg), tools/hwla2vcd.py
#                       of asylum:debug:HWLA to the work root. Their
#                       directories are found from the path of one of their
#                       HDL files in the EDAM file of FuseSoC (*.eda.yml).
#                vcd <args> : post_run, hwla2vcd.py (asylum:debug:HWLA
#                       >= 3.1.0) rebuilds hwla.vcd from hwla.bin (written by
#                       picosoc_hwla_dump in hwla_check.cfg) with the
#                       argument file <args> of tools/hwla (configuration of
#                       the HWLA, named signals of the probes) : one complete
#                       capture, its trigger wire and the named signals.
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-27  1.0      mrosiere Created
#-----------------------------------------------------------------------------

set -e

# Root of the core that holds the HDL file $1 (path in the EDAM file)
core_root() {
    local f
    f=$(grep -ho "[^ '\"]*/hdl/$1" ./*.eda.yml | head -n 1)
    [ -n "$f" ] || { echo "hwla_tools.sh : hdl/$1 not in the EDAM file" >&2; exit 1; }
    dirname "$(dirname "$f")"
}

case $1 in
    copy)
        mkdir -p openocd
        cp "$(core_root jtag_axis.vhd)/tools/openocd/jtag_axis.tcl" openocd/
        cp "$(core_root hwla.vhd)/tools/hwla2vcd.py" .
        echo "hwla_tools.sh : openocd/jtag_axis.tcl, hwla2vcd.py copied" ;;
    vcd)
        python3 hwla2vcd.py hwla.bin --args-file "$2" -o hwla.vcd
        for name in trigger dcs daddr drdata ics iaddr idata; do
            grep -q "^\$var wire [0-9]* [^ ]* $name " hwla.vcd || { echo "hwla_tools.sh : no signal $name in hwla.vcd"; exit 1; }
        done
        echo "hwla_tools.sh : hwla.bin decoded by hwla2vcd.py : hwla.vcd" ;;
    *)
        echo "Usage : $0 copy | vcd <args file>"
        exit 1 ;;
esac
