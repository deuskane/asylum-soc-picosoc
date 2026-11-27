#-----------------------------------------------------------------------------
# Title      : Short OpenOCD commands for the PicoSoC CPUs
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : picosoc_cmds.tcl
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Commands for the telnet session of OpenOCD (type picosoc_help),
#              sourced by picosoc.cfg after init. A CPU is given by its
#              OpenOCD name (user.cpu0, supervisor.cpu), a short name (user,
#              user0, user1 ..., sup, supervisor) or its index in "status";
#              without it, the selected CPU (select).
#              The debug units of PicoSoC have no System Bus Access : memory
#              is read / written by the CPU itself (program buffer), only
#              while it is halted. read_mem / write_mem halt a running CPU
#              for the access, then resume it.
#              The OpenOCD commands keep their names (halt, resume, step,
#              reg, mdw, mww, bp ...).
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-27  1.0      mrosiere Created
# 2026-11-27  1.1      mrosiere Help : picosoc_inject (16 bits), picosoc_inject_cpu
#-----------------------------------------------------------------------------

# OpenOCD names of x0 to x31 (x8 is fp, also named s0)
set PICOSOC_GPRS {zero ra sp gp tp t0 t1 t2 fp s1 a0 a1 a2 a3 a4 a5 a6 a7
                  s2 s3 s4 s5 s6 s7 s8 s9 s10 s11 t3 t4 t5 t6}

# Causes of a halt (dcsr.cause, RISC-V debug specification)
set PICOSOC_HALT_CAUSE {1 ebreak 2 trigger 3 haltreq 4 step 5 resethaltreq}

proc picosoc_help {} {
    return {
PicoSoC commands       [cpu] : user.cpu0 / user / user0, supervisor.cpu / sup,
                               or the index of 'status' (default : selected)
 CPUs
   status                   state and pc of every CPU (* = selected)
   select <cpu>             select a CPU
   stop [cpu] / stop_all    halt one CPU / every CPU
   run  [cpu] / run_all     resume one CPU / every CPU
   stepi [n]                execute n instructions (selected CPU, halted)
   halt_cause [cpu]         why the CPU is halted (dcsr.cause)
 Registers (CPU halted)
   pc [cpu] / set_pc <addr>
   regs                     the 32 registers and pc
   read_reg <reg>           e.g. read_reg a0, read_reg x10
   write_reg <reg> <value>
 Memory (a running CPU is halted for the access, then resumed)
   read_mem  <addr> [n]     n words of 32 bits
   write_mem <addr> <value> one word of 32 bits (no read back)
   read_byte  <addr> [n]    n bytes (peripheral registers of 8 bits)
   write_byte <addr> <value> (no read back : reading a peripheral register
                            can change it, e.g. the UART data register)
 Breakpoints
   bp_add <addr> / bp_del <addr>   hardware breakpoint (needs triggers)
 SoC (injection / status TAP, HWLA)
   picosoc_status, picosoc_inject <errors> (raw 16 bits : [2:0] outside the CPUs,
     [6:4] [10:8] [14:12] inside the CPU copy 0 1 2, a write of these also writes [2:0])
   picosoc_inject_cpu <copy 0..2> <mask 3 bits> (inside a CPU copy, one pulse per bit)
   picosoc_hwla_status, picosoc_hwla_dump <file>
}
}

#--------------------------------------
# Helpers
#--------------------------------------
# OpenOCD target of a CPU name, short name or index ("" : the selected one)
proc picosoc_cpu {{cpu ""}} {
    set names [target names]
    if {$names eq ""} {
        return -code error "no CPU target in the chain (a bitstream with a CPU debugger : USER_CPU_DEBUG_ENABLE / SUPERVISOR_CPU_DEBUG_ENABLE)"
    }
    if {$cpu eq ""} {
        return [target current]
    }
    if {[string is integer -strict $cpu]} {
        set t [lindex $names $cpu]
        if {$t eq ""} {
            return -code error "no CPU number $cpu (status)"
        }
        return $t
    }
    switch -- $cpu {
        user       { set cpu user.cpu0 }
        sup        -
        supervisor { set cpu supervisor.cpu }
    }
    if {[regexp {^user([0-9]+)$} $cpu -> n]} {
        set cpu user.cpu$n
    }
    if {$cpu ni $names} {
        return -code error "no CPU $cpu : [join $names {, }]"
    }
    return $cpu
}

# Run body with the CPU cpu selected, then select the previous one again
proc picosoc_with_cpu {cpu body} {
    set t   [picosoc_cpu $cpu]
    set old [target current]
    targets $t
    set rc [catch {uplevel 1 $body} res]
    targets $old
    return -code $rc $res
}

# Run body with the selected CPU halted (halted for the body if it runs)
proc picosoc_with_halted {body} {
    set t   [target current]
    set was [$t curstate]
    if {$was eq "running"} {
        halt
    } elseif {$was ne "halted"} {
        return -code error "$t : $was (reset of the board : jtag arp_init, then $t arp_examine)"
    }
    set rc [catch {uplevel 1 $body} res]
    if {$was eq "running"} {
        resume
    }
    return -code $rc $res
}

# Value (hex) of a register of the selected CPU
proc picosoc_reg {name} {
    set out [reg $name force]
    if {![regexp {(0x[0-9a-fA-F]+)} $out -> v]} {
        return -code error "reg $name : $out"
    }
    return $v
}

#--------------------------------------
# CPUs
#--------------------------------------
proc status {} {
    set s ""
    set i 0
    foreach t [target names] {
        set mark  [expr {$t eq [target current] ? "*" : " "}]
        set state [$t curstate]
        set extra ""
        if {$state eq "halted"} {
            catch {picosoc_with_cpu $t {set extra "pc=[picosoc_reg pc]  [halt_cause]"}}
        }
        append s [format "%s%d %-16s %-10s %s\n" $mark $i $t $state $extra]
        incr i
    }
    return [string trimright $s]
}

proc select {cpu} {
    targets [picosoc_cpu $cpu]
    return "selected : [target current]"
}

proc stop {{cpu ""}} {
    picosoc_with_cpu $cpu {halt}
    return "[picosoc_cpu $cpu] halted, pc=[pc $cpu]"
}

proc run {{cpu ""}} {
    picosoc_with_cpu $cpu {resume}
    return "[picosoc_cpu $cpu] running"
}

proc stop_all {} {
    foreach t [target names] {
        if {[$t curstate] eq "running"} {
            catch {picosoc_with_cpu $t {halt}}
        }
    }
    return [status]
}

proc run_all {} {
    foreach t [target names] {
        if {[$t curstate] eq "halted"} {
            catch {picosoc_with_cpu $t {resume}}
        }
    }
    return [status]
}

proc stepi {{n 1}} {
    for {set i 0} {$i < $n} {incr i} {
        step
    }
    return "pc=[pc]"
}

proc halt_cause {{cpu ""}} {
    global PICOSOC_HALT_CAUSE
    picosoc_with_cpu $cpu {
        set dcsr  [picosoc_reg dcsr]
        set cause [expr {($dcsr >> 6) & 7}]
        set text  "?"
        if {[dict exists $PICOSOC_HALT_CAUSE $cause]} {
            set text [dict get $PICOSOC_HALT_CAUSE $cause]
        }
        return "cause=$cause ($text)"
    }
}

#--------------------------------------
# Registers
#--------------------------------------
proc pc {{cpu ""}} {
    picosoc_with_cpu $cpu {
        set t [target current]
        if {[$t curstate] ne "halted"} {
            return "$t : [$t curstate] (stop it to read pc)"
        }
        return [picosoc_reg pc]
    }
}

proc set_pc {addr} {
    reg pc $addr
    return "pc=[picosoc_reg pc]"
}

proc regs {} {
    global PICOSOC_GPRS
    set s ""
    set i 0
    foreach r $PICOSOC_GPRS {
        append s [format "x%-2d %-4s %s" $i $r [picosoc_reg $r]]
        append s [expr {$i % 4 == 3 ? "\n" : "   "}]
        incr i
    }
    return "${s}pc       [picosoc_reg pc]"
}

proc read_reg {name} {
    return "$name = [picosoc_reg $name]"
}

proc write_reg {name value} {
    reg $name $value
    return "$name = [picosoc_reg $name]"
}

#--------------------------------------
# Memory, breakpoints
#--------------------------------------
proc read_mem {addr {n 1}} {
    picosoc_with_halted {set r [mdw $addr $n]}
    return $r
}

# No read back : a peripheral register can change when it is read (e.g. the
# data register of the UART pops its FIFO)
proc write_mem {addr value} {
    picosoc_with_halted {mww $addr $value}
    return "[format 0x%08x $addr] <- $value"
}

proc read_byte {addr {n 1}} {
    picosoc_with_halted {set r [mdb $addr $n]}
    return $r
}

proc write_byte {addr value} {
    picosoc_with_halted {mwb $addr $value}
    return "[format 0x%08x $addr] <- $value"
}

proc bp_add {addr} {
    bp $addr 4 hw
}

proc bp_del {addr} {
    rbp $addr
}
