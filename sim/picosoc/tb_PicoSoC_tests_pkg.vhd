-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_tests_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_tests_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenarios of tb_PicoSoC : names (valid items of TESTS_LIST),
--              firmware and configurations where each one applies, and
--              dispatch (run_test) to the package of each scenario
--              (tb_PicoSoC_<name>_pkg) ; an integration scenario test_<ip>
--              has the name of its firmware (esw/test/test_<ip>.c)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC)
-- 2026-11-21  1.1      mrosiere Integration scenarios test_<ip>
-- 2026-11-21  1.2      mrosiere test_i2c
-- 2026-11-21  1.3      mrosiere test_pwm
-- 2026-11-21  1.4      mrosiere hwla (DEBUG_ENABLE), debug_uart_tx_o and
--                               user ROM copy of the testbench
-- 2026-11-22  1.5      mrosiere pad_mux (functions of the UART pads) :
--                               CTS* of the cable, UART pads CTS* and RTS*
-- 2026-11-22  1.6      mrosiere jtag_chain, jtag_inject, jtag_status (JTAG
--                               BFM, JTAG chain of the configuration)
-- 2026-11-22  1.7      mrosiere jtag_cpu_user, jtag_cpu_supervisor
-- 2026-11-23  1.8      mrosiere bitbang_chain, bitbang_inject, bitbang_cpu,
--                               (JTAG over the UART pads),
--                               jtag_last (stages without TAP at the end of
--                               the chain)
-- 2026-11-23  1.9      mrosiere uart : CTS* of the cable (echo on a quiet
--                               line)
-- 2026-11-23  1.10     mrosiere mux_sel (debug_mux_sel_i) to the scenarios of
--                               the UART pads
-- 2026-11-24  1.11     mrosiere rbb_if, bitbang (t_rbb_answers) of the
--                               remote_bitbang BFM to the scenarios bitbang_*,
--                               jtag_last
-- 2026-11-26  1.12     mrosiere jtag_glitch (bounces on TCK of the JTAG
--                               pads)
-- 2026-11-26  1.13     mrosiere trap_cpu0, trap_cpu1, trap_reset, trap_tap
--                               (trap of the error injection)
-- 2026-11-27  1.14     mrosiere hwla : mux_sel and jtag_if (captures read
--                               through the TAP of jtag_axis, HWLA_LINK "jtag")
-- 2026-11-27  1.15     mrosiere sequence (firmware user_loop : the xorwow
--                               lines, LED0 = switches)
-- 2026-11-27  1.16     mrosiere hwla, hwla_tap : HWLA triggered by the
--                               error injection (button, TAP), every safety
-- 2026-11-27  1.17     mrosiere jtag_inject_cpu (INJECT [6:4], [10:8], [14:12] :
--                               injection inside the CPUs)
-- 2026-11-27  1.18     mrosiere Student branch : fault_none (SAFETY none, the
--                               firmware derails, the supervisor sees nothing)
-- 2026-11-27  1.19     mrosiere Student branch : the scenarios of the targets
--                               of the labs only (switch, it_user, sequence,
--                               fault_*, hwla, test_<ip>), firmwares user,
--                               user_loop and test_<ip>
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_i2c;
use     bitvis_vip_i2c.i2c_bfm_pkg.all;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;

library asylum;
use     asylum.string_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_tests_pkg is

  -- Integration firmwares (esw/test/test_<ip>.c) : each one is also the name of
  -- the scenario that checks it
  constant C_INTEGRATION : string := "test_gpio,test_uart,test_spi,test_timer,test_crc,test_spinlock,test_gic,test_ram,test_i2c,test_pwm";

  -- Names of the scenarios (valid items of TESTS_LIST)
  constant C_TESTS : string := "switch,it_user,sequence,fault_none,fault_lock_step,fault_tmr,hwla," & C_INTEGRATION;

  -- Firmware in the user ROM (generator of the target, FIRMWARE generic)
  constant C_FIRMWARES : string := "user,user_loop," & C_INTEGRATION;

  -- True when the scenario name applies to the firmware and the configuration
  function test_applies
    (name       : string
    ;firmware   : string
    ;supervisor : boolean
    ;safety     : string
    ;fault      : boolean
    ;debug      : boolean
    ) return boolean;

  -- Run the scenario name
  procedure run_test
    (constant name     : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   it_user  : out   std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   jtag_if  : inout t_jtag_if
    ;signal   i2c_if   : inout t_i2c_if
    ;signal   pwm      : in    std_logic
    ;signal   debug_tx : in    std_logic
    ;signal   rom_addr : out   std_logic_vector
    ;signal   rom_data : in    std_logic_vector
    );

end package tb_PicoSoC_tests_pkg;

package body tb_PicoSoC_tests_pkg is

  function test_applies
    (name       : string
    ;firmware   : string
    ;supervisor : boolean
    ;safety     : string
    ;fault      : boolean
    ;debug      : boolean
    ) return boolean is
    -- esw/demo/user.c
    constant C_USER : boolean := string_eq(firmware, "user");
  begin
    if    string_eq(name, "switch"         ) then return C_USER;
    elsif string_eq(name, "it_user"        ) then return C_USER;
    elsif string_eq(name, "sequence"       ) then return string_eq(firmware, "user_loop");
    elsif string_eq(name, "fault_none"     ) then return C_USER and supervisor and fault and string_eq(safety, "none");
    elsif string_eq(name, "fault_lock_step") then return C_USER and supervisor and fault and string_eq(safety, "lock-step");
    elsif string_eq(name, "fault_tmr"      ) then return C_USER and supervisor and fault and string_eq(safety, "tmr");
    elsif string_eq(name, "hwla"           ) then return C_USER and not supervisor and fault and debug;
    elsif list_contains(C_INTEGRATION, name ) then return string_eq(firmware, name); -- test_<ip> : its firmware only
    else                                          return false;
    end if;
  end function;

  procedure run_test
    (constant name     : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   it_user  : out   std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   jtag_if  : inout t_jtag_if
    ;signal   i2c_if   : inout t_i2c_if
    ;signal   pwm      : in    std_logic
    ;signal   debug_tx : in    std_logic
    ;signal   rom_addr : out   std_logic_vector
    ;signal   rom_data : in    std_logic_vector
    ) is
  begin
    if    string_eq(name, "switch")
    then
      work.tb_PicoSoC_switch_pkg.run(cfg, clk, switch, led0, led_diff);
    elsif string_eq(name, "it_user")
    then
      work.tb_PicoSoC_it_user_pkg.run(cfg, clk, switch, it_user, led0, led1, led_diff);
    elsif string_eq(name, "sequence")
    then
      work.tb_PicoSoC_sequence_pkg.run(cfg, clk, switch, led0, led_diff, uart_tx);
    elsif string_eq(name, "fault_none")
    then
      work.tb_PicoSoC_fault_none_pkg.run(cfg, clk, switch, inject, led0, led_diff);
    elsif string_eq(name, "fault_lock_step")
    then
      work.tb_PicoSoC_fault_lock_step_pkg.run(cfg, clk, switch, inject, led0, led_diff);
    elsif string_eq(name, "fault_tmr")
    then
      work.tb_PicoSoC_fault_tmr_pkg.run(cfg, clk, switch, inject, led0, led_diff);
    elsif string_eq(name, "hwla")
    then
      work.tb_PicoSoC_hwla_pkg.run(cfg, false, clk, switch, mux_sel, inject, led0, led_diff, debug_tx, jtag_if, rom_addr, rom_data);
    elsif string_eq(name, "test_gpio")
    then
      work.tb_PicoSoC_test_gpio_pkg.run(cfg, clk, switch, led0, led1, uart_tx);
    elsif string_eq(name, "test_uart")
    then
      work.tb_PicoSoC_test_uart_pkg.run(cfg, led0, led1, uart_rx, uart_tx);
    elsif string_eq(name, "test_spi")
    then
      wait_pass(name, uart_tx, cfg);  -- checked by the firmware with the SPI flash model
    elsif string_eq(name, "test_timer")
    then
      work.tb_PicoSoC_test_timer_pkg.run(cfg, led0, uart_tx);
    elsif string_eq(name, "test_crc")
    then
      wait_pass(name, uart_tx, cfg);  -- no pin : checked by the firmware
    elsif string_eq(name, "test_spinlock")
    then
      wait_pass(name, uart_tx, cfg);  -- no pin : checked by the firmware
    elsif string_eq(name, "test_gic")
    then
      work.tb_PicoSoC_test_gic_pkg.run(cfg, clk, it_user, led0, led1, uart_tx);
    elsif string_eq(name, "test_ram")
    then
      wait_pass(name, uart_tx, cfg);  -- no pin : checked by the firmware
    elsif string_eq(name, "test_i2c")
    then
      work.tb_PicoSoC_test_i2c_pkg.run(cfg, clk, switch, led0, i2c_if, uart_tx);
    elsif string_eq(name, "test_pwm")
    then
      work.tb_PicoSoC_test_pwm_pkg.run(cfg, clk, switch, led0, pwm, uart_tx);
    else
      alert(TB_ERROR, "Unknown test " & name, C_TB_SCOPE);
    end if;
  end procedure;

end package body tb_PicoSoC_tests_pkg;
