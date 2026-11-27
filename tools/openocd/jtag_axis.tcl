#-----------------------------------------------------------------------------
# Title      : OpenOCD procedures of jtag_axis
# Project    : Asylum
#-----------------------------------------------------------------------------
# File       : jtag_axis.tcl
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Copy in PicoSoC of tools/openocd/jtag_axis.tcl of
#              asylum-debug-jtag 1.3.0 (keep the two files identical),
#              sourced by picosoc.cfg.
#              OpenOCD 0.12, sourced after init (exec stage). <tap> is the
#              OpenOCD name of the jtag_axis TAP (e.g. axis.tap, declared
#              with -irlen 5) :
#                jtag_axis_config <tap>       : CONFIG register, returned as
#                    a dict (tx_enable, tx_empty, tx_full, rx_enable,
#                    rx_empty, rx_full, data_width)
#                jtag_axis_pop <tap> [n]      : reads up to n words (1 by
#                    default) of the TX FIFO (system to JTAG), stops on an
#                    empty FIFO, returns the list of the words read
#                jtag_axis_push <tap> <words> : writes the words to the RX
#                    FIFO (JTAG to system), stops on the first word refused
#                    (FIFO full), returns the number of words written
#              Opcodes (IR of 5 bits) : CONFIG 2, TX 3, RX 4 (jtag_pkg).
#              Words of up to 62 bits : a scan of DATA_WIDTH + 1 bits read as
#              a positive Jim Tcl integer (signed 64 bits) ; the procedures
#              stop with an error on a wider CONFIG.
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-26  1.0      mrosiere Created
# 2026-11-27  1.1      mrosiere CONFIG of 16 bits (no FIFO depth), words of up to
#                               62 bits checked
#-----------------------------------------------------------------------------

# CONFIG register (16 bits) of the jtag_axis TAP <tap>, as a dict
proc jtag_axis_config {tap} {
    irscan $tap 2
    set c [expr 0x[drscan $tap 16 0]]
    return [dict create \
                tx_enable  [expr {$c         & 1}] \
                tx_empty   [expr {($c >>  1) & 1}] \
                tx_full    [expr {($c >>  2) & 1}] \
                rx_enable  [expr {($c >>  4) & 1}] \
                rx_empty   [expr {($c >>  5) & 1}] \
                rx_full    [expr {($c >>  6) & 1}] \
                data_width [expr {($c >>  8) & 0xff}]]
}

# DATA_WIDTH of CONFIG, at most 62 (scan of 63 bits, a positive integer)
proc jtag_axis_width {tap} {
    set width [dict get [jtag_axis_config $tap] data_width]
    if {$width > 62} {
        error "jtag_axis : DATA_WIDTH $width, the procedures handle up to 62 bits"
    }
    return $width
}

# Up to n words of the TX FIFO : one TX scan per word ({word, valid}, the
# word is removed in Update-DR when valid), stops on an empty FIFO
proc jtag_axis_pop {tap {n 1}} {
    set width [jtag_axis_width $tap]
    irscan $tap 3
    set words {}
    for {set i 0} {$i < $n} {incr i} {
        set v [expr 0x[drscan $tap [expr {$width + 1}] 0]]
        if {($v & 1) == 0} {
            break
        }
        lappend words [expr {$v >> 1}]
    }
    return $words
}

# Words to the RX FIFO : one RX scan per word (word shifted in the bits
# width downto 1, bit 0 captured : accepted), stops on the first word
# refused (RX FIFO full), returns the number of words written
proc jtag_axis_push {tap words} {
    set width [jtag_axis_width $tap]
    irscan $tap 4
    set n 0
    foreach w $words {
        set v [expr 0x[drscan $tap [expr {$width + 1}] [format 0x%x [expr {$w << 1}]]]]
        if {($v & 1) == 0} {
            break
        }
        incr n
    }
    return $n
}
