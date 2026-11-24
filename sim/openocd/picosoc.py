#-----------------------------------------------------------------------------
# Title      : GDB scenario of the PicoSoC co-simulations
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : picosoc.py
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: gdb-multiarch -batch -x picosoc.py, on the GDB server of
#              OpenOCD (remote_bitbang.cfg, picosoc.cfg) connected to
#              tb_PicoSoC_openocd (firmware esw/demo/user.c : LED0 = switches),
#              through the JTAG pins (debug_mux_sel_i 10) or JTAG over the
#              UART (debug_mux_sel_i 11) :
#                chain  : OpenOCD found every TAP with its IDCODE
#                halt   : GDB halts the user hart, pc in the user ROM, sp in
#                         the stack of the firmware (GDB reads the RAM of the
#                         firmware only : mem)
#                resume : the user hart runs again (dmstatus)
#                inject : INJECT of the injection / status TAP
#                         (picosoc_inject : irscan, drscan) : an error in
#                         CPU1 raises the difference flag CPU0 vs CPU1, read
#                         back by the next scan
#              The testbench checks the difference flag on led_diff_o and
#              that the firmware runs after the session.
#              Prints ok / ERROR for each check, then SCENARIO PASS / FAIL.
#              Generic helpers in gdb_lib.py of asylum:processor:WardRV
#              (openocd/gdb_lib.py of the work root, next to this file).
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-24  1.0      mrosiere Created
#-----------------------------------------------------------------------------

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from   gdb_lib import check, run, u32, cause, monitor_value, connect, resume, openocd_log, main
from   gdb_lib import HALTREQ

# JTAG chain of tb_PicoSoC_openocd (picosoc.cfg) : TAP, IDCODE
CHAIN         = {"picosoc.inject" : 0x10003001,
                 "user.cpu"       : 0x10001001}
ROM_SIZE      = 0x1000                             # user ROM (rvcc_gen, addr_width 10)
RAM           = (0x80000040, 0x80000100)           # RAM_GLB and RAM_LOC of link.ld (rvcc_gen)
STACK         = (0x80000080, 0x80000100)           # RAM_LOC

#--------------------------------------------
# Helpers
#--------------------------------------------
def inject(bits):
    """
    INJECT of the injection / status TAP (picosoc_inject of picosoc.cfg)
    :param bits: errors injected, bit i in CPU i
    :return: the captured difference flags (bit 0 CPU0 vs CPU1)
    """
    return int(run(f"monitor picosoc_inject 0x{bits:x}").split()[-1], 16)

#--------------------------------------------
# Steps
#--------------------------------------------
def step_chain():
    log = openocd_log()
    for tap, idcode in CHAIN.items():
        check(f"JTAG tap: {tap} tap/device found: 0x{idcode:08x}" in log, f"{tap} : IDCODE 0x{idcode:08X}")
    check("UNEXPECTED" not in log, "no unexpected IDCODE")
    check("Examined RISC-V core" in log, "user CPU examined")

#--------------------------------------------
#--------------------------------------------
def step_halt():
    run("set architecture riscv:rv32")
    # GDB reads the memory of the RAM only : the user ROM is not on the data
    # bus, a read of the code at pc would reach the peripherals
    run(f"mem 0x{RAM[0]:08x} 0x{RAM[1]:08x} rw")
    connect()                                      # the hart halts
    pc = u32("$pc")
    check(pc < ROM_SIZE, f"user hart halted in the user ROM : pc 0x{pc:08X}")
    check(cause() == HALTREQ, "dcsr.cause : halt request")
    sp = u32("$sp")
    check(STACK[0] <= sp < STACK[1], f"sp 0x{sp:08X} in the stack of the firmware")

#--------------------------------------------
#--------------------------------------------
def step_resume():
    resume()
    dmstatus = monitor_value("riscv dmi_read 0x11")
    check((dmstatus >> 10) & 3 == 3, f"dmstatus 0x{dmstatus:08X} : allrunning, anyrunning")

#--------------------------------------------
#--------------------------------------------
def step_inject():
    check(inject(0b010) == 0, "INJECT : no difference before the injection, error injected in CPU1")
    for _ in range(20):                            # until CPU1 differs
        run("monitor runtest 100")
        diff = inject(0b010)
        if diff:
            break
    check(diff == 0b001, f"INJECT : difference flags 0b{diff:03b}, CPU0 vs CPU1")
    check(inject(0b000) == 0b001, "INJECT : end of the injection, the flag is sticky")

main([step_chain, step_halt, step_resume, step_inject])
