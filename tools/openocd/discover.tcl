#-----------------------------------------------------------------------------
# Title      : OpenOCD discovery of the JTAG chain of PicoSoC
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : discover.tcl
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: OpenOCD 0.12, sourced by discover.cfg and picosoc.cfg, in the
#              configuration stage (after an adapter file, no TAP declared,
#              before init) :
#                picosoc_tap <idcode> : chip and TAP of a PicoSoC IDCODE
#                picosoc_discover     : probes the chain, prints it and
#                                       returns it as picosoc_chain
#              "jtag init" starts the adapter and probes the chain after
#              Test-Logic-Reset (OpenOCD autoprobe) : it declares the TAPs
#              auto0.tap, auto1.tap ... from TDO, with the IDCODE read from
#              TDO and the IR length from the Capture-IR value. They stay
#              the TAPs of the session (OpenOCD 0.12 can neither rename nor
#              remove a TAP) : init checks them again, and picosoc.cfg
#              creates the targets on them. "jtag cget -idcode" needs the
#              exec stage : the IDCODEs come from scan_chain.
#              PicoSoC IDCODEs (PICOSOC_JTAG_IDCODE_* of PicoSoC_pkg) :
#                0x10001001 + i x 0x10000 : user CPU of cluster i (user cpu<i>)
#                0x10002001               : supervisor CPU (supervisor cpu)
#                0x10003001               : injection / status TAP
#                                           (picosoc inject)
#                0x10004001               : jtag_axis of the HWLA captures,
#                                           HWLA_LINK "jtag" (picosoc hwla)
#              Any other IDCODE is named "unknown tap<k>" ; a TAP without
#              IDCODE (BYPASS after Test-Logic-Reset) reads 0x00000000.
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-26  1.0      mrosiere Created from discover.cfg (shared with
#                               picosoc.cfg)
# 2026-11-27  1.1      mrosiere 0x10004001 : picosoc hwla (jtag_axis of the
#                               HWLA captures)
#-----------------------------------------------------------------------------

# Chip and TAP of a PicoSoC IDCODE (the names of picosoc_chain), empty if the
# IDCODE is not one of PicoSoC
proc picosoc_tap {idcode} {
    if {$idcode == 0x10003001} {
        return "picosoc inject"
    }
    if {$idcode == 0x10004001} {
        return "picosoc hwla"
    }
    if {$idcode == 0x10002001} {
        return "supervisor cpu"
    }
    # 0x10001001 + i x 0x10000 : cluster i in the bits 27 to 16
    if {($idcode & 0xf000ffff) == 0x10001001} {
        return "user cpu[expr {($idcode >> 16) & 0xfff}]"
    }
    return ""
}

# Probes the chain (jtag init), prints the number of TAPs, the IDCODE and the
# PicoSoC name of each TAP (from TDO), returns the chain : chip, TAP, IDCODE
# of each TAP, from TDO (the list picosoc_chain of picosoc.cfg)
proc picosoc_discover {} {
    jtag init

    # scan_chain : 2 title lines, then a line per TAP (#, TapName, Enabled,
    # IdCode, Expected, ...)
    set chain {}
    set lines {}
    set k 0
    foreach line [lrange [split [scan_chain] \n] 2 end] {
        if {[llength $line] < 5} {
            continue
        }
        set idcode [lindex $line 3]
        set name   [picosoc_tap $idcode]
        if {$name eq ""} {
            set name "unknown tap$k"
        }
        lappend lines "TAP $k : IDCODE $idcode : [join $name .]"
        lappend chain {*}$name $idcode
        incr k
    }

    echo "PicoSoC JTAG chain : $k TAP(s), from TDO"
    foreach line $lines {
        echo $line
    }
    if {$k == 0} {
        echo "No TAP : check the cable, debug_mux_sel_i (10 or 11) and the bitstream"
    }
    return $chain
}
