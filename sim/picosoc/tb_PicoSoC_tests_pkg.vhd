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
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_i2c;
use     bitvis_vip_i2c.i2c_bfm_pkg.all;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;
use     asylum_uvvm.rbb_bfm_pkg.all;

library asylum;
use     asylum.string_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_tests_pkg is

  -- Integration firmwares (esw/test/test_<ip>.c) : each one is also the name of
  -- the scenario that checks it
  constant C_INTEGRATION : string := "test_gpio,test_uart,test_spi,test_timer,test_crc,test_spinlock,test_gic,test_ram,test_mailbox,test_i2c,test_pwm";

  -- Names of the scenarios (valid items of TESTS_LIST)
  constant C_TESTS : string := "switch,it_user,uart,fault_lock_step,fault_tmr,fault_diff,hwla,hello,pad_mux,jtag_chain,jtag_inject,jtag_status,jtag_cpu_user,jtag_cpu_supervisor,bitbang_chain,bitbang_inject,bitbang_cpu,jtag_last,jtag_glitch,trap_cpu0,trap_cpu1,trap_reset,trap_tap," & C_INTEGRATION;

  -- Firmware in the user ROM (generator of the target, FIRMWARE generic)
  constant C_FIRMWARES : string := "identity,user,user_uart,user_uart_spi,user_uart_spi_mem,hello," & C_INTEGRATION;

  -- True when the scenario name applies to the firmware and the configuration
  function test_applies
    (name       : string
    ;firmware   : string
    ;supervisor : boolean
    ;safety     : string
    ;fault      : boolean
    ;debug      : boolean
    ;jtag       : t_jtag_chain
    ) return boolean;

  -- SPI byte of the "Loop" lines printed by the firmware
  function to_spi_byte
    (firmware   : string
    ) return t_spi_byte;

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
    ;signal   cts_b    : out   std_logic
    ;signal   cts_pad  : in    std_logic
    ;signal   rts_pad  : in    std_logic
    ;signal   jtag_if  : inout t_jtag_if
    ;signal   rbb_if   : inout t_rbb_if
    ;signal   bitbang  : in    t_rbb_answers
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
    ;jtag       : t_jtag_chain
    ) return boolean is
    -- esw/demo/user.c, with or without UART
    constant C_USER : boolean := list_contains("user,user_uart,user_uart_spi,user_uart_spi_mem", firmware);
    constant C_UART : boolean := list_contains(     "user_uart,user_uart_spi,user_uart_spi_mem", firmware);
  begin
    if    string_eq(name, "switch"         ) then return not string_eq(firmware, "hello") and not list_contains(C_INTEGRATION, firmware);
    elsif string_eq(name, "it_user"        ) then return C_USER;
    elsif string_eq(name, "uart"           ) then return C_UART;
    elsif string_eq(name, "fault_lock_step") then return C_USER and supervisor and fault and string_eq(safety, "lock-step");
    elsif string_eq(name, "fault_tmr"      ) then return C_USER and supervisor and fault and string_eq(safety, "tmr");
    elsif string_eq(name, "fault_diff"     ) then return C_USER and not supervisor and fault and not string_eq(safety, "none");
    elsif string_eq(name, "hwla"           ) then return C_USER and not supervisor and fault and not string_eq(safety, "none") and debug;
    elsif string_eq(name, "hello"          ) then return string_eq(firmware, "hello");
    elsif string_eq(name, "pad_mux"        ) then return C_UART;
    elsif string_eq(name, "jtag_chain"     ) then return C_USER and jtag.nb_tap > 0;
    elsif string_eq(name, "jtag_inject"    ) then return C_USER and debug and fault and (not supervisor or string_eq(safety, "lock-step"));
    elsif string_eq(name, "jtag_status"    ) then return C_USER and debug;
    elsif string_eq(name, "jtag_cpu_user"      ) then return C_USER and jtag.user       >= 0;
    elsif string_eq(name, "jtag_cpu_supervisor") then return C_USER and jtag.supervisor >= 0;
    elsif string_eq(name, "bitbang_chain"  ) then return C_USER and jtag.nb_tap > 0;
    elsif string_eq(name, "bitbang_inject" ) then return C_USER and debug and fault and supervisor and string_eq(safety, "lock-step");
    elsif string_eq(name, "bitbang_cpu"    ) then return C_USER and jtag.user >= 0;
    elsif string_eq(name, "jtag_last"      ) then return C_USER and jtag.user >= 0;
    elsif string_eq(name, "jtag_glitch"    ) then return C_USER and jtag.nb_tap > 0;
    elsif string_eq(name, "trap_cpu0"      ) then return C_USER and supervisor and fault and string_eq(safety, "lock-step");
    elsif string_eq(name, "trap_cpu1"      ) then return C_USER and supervisor and fault and string_eq(safety, "lock-step");
    elsif string_eq(name, "trap_reset"     ) then return C_USER and supervisor and fault and string_eq(safety, "lock-step") and jtag.supervisor >= 0;
    elsif string_eq(name, "trap_tap"       ) then return C_USER and fault and string_eq(safety, "none") and debug and jtag.user >= 0;
    elsif list_contains(C_INTEGRATION, name ) then return string_eq(firmware, name); -- test_<ip> : its firmware only
    else                                          return false;
    end if;
  end function;

  function to_spi_byte
    (firmware   : string
    ) return t_spi_byte is
  begin
    if    string_eq(firmware, "user_uart_spi"    ) then return SPI_LOOPBACK;
    elsif string_eq(firmware, "user_uart_spi_mem") then return SPI_MEMORY;
    else                                                return SPI_NONE;
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
    ;signal   cts_b    : out   std_logic
    ;signal   cts_pad  : in    std_logic
    ;signal   rts_pad  : in    std_logic
    ;signal   jtag_if  : inout t_jtag_if
    ;signal   rbb_if   : inout t_rbb_if
    ;signal   bitbang  : in    t_rbb_answers
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
    elsif string_eq(name, "uart")
    then
      work.tb_PicoSoC_uart_pkg.run(cfg, clk, switch, it_user, led0, led1, uart_rx, uart_tx, cts_b);
    elsif string_eq(name, "fault_lock_step")
    then
      work.tb_PicoSoC_fault_lock_step_pkg.run(cfg, clk, switch, inject, led0, led_diff);
    elsif string_eq(name, "fault_tmr")
    then
      work.tb_PicoSoC_fault_tmr_pkg.run(cfg, clk, switch, inject, led0, led_diff);
    elsif string_eq(name, "fault_diff")
    then
      work.tb_PicoSoC_fault_diff_pkg.run(cfg, clk, switch, inject, led0, led_diff);
    elsif string_eq(name, "hwla")
    then
      work.tb_PicoSoC_hwla_pkg.run(cfg, clk, switch, inject, led0, led_diff, debug_tx, rom_addr, rom_data);
    elsif string_eq(name, "pad_mux")
    then
      work.tb_PicoSoC_pad_mux_pkg.run(cfg, clk, switch, mux_sel, inject, led0, uart_rx, uart_tx, cts_b, cts_pad, rts_pad, jtag_if, debug_tx);
    elsif string_eq(name, "jtag_chain")
    then
      work.tb_PicoSoC_jtag_chain_pkg.run(cfg, clk, switch, mux_sel, led0, cts_pad, jtag_if);
    elsif string_eq(name, "jtag_inject")
    then
      work.tb_PicoSoC_jtag_inject_pkg.run(cfg, clk, switch, mux_sel, led0, led_diff, jtag_if);
    elsif string_eq(name, "jtag_status")
    then
      work.tb_PicoSoC_jtag_status_pkg.run(cfg, clk, switch, mux_sel, it_user, inject, led0, led1, led_diff, jtag_if);
    elsif string_eq(name, "jtag_cpu_user")
    then
      work.tb_PicoSoC_jtag_cpu_pkg.run(cfg, false, clk, switch, mux_sel, inject, led0, led_diff, jtag_if);
    elsif string_eq(name, "jtag_cpu_supervisor")
    then
      work.tb_PicoSoC_jtag_cpu_pkg.run(cfg, true , clk, switch, mux_sel, inject, led0, led_diff, jtag_if);
    elsif string_eq(name, "bitbang_chain")
    then
      work.tb_PicoSoC_bitbang_chain_pkg.run(cfg, clk, switch, mux_sel, led0, rbb_if, bitbang);
    elsif string_eq(name, "bitbang_inject")
    then
      work.tb_PicoSoC_bitbang_inject_pkg.run(cfg, clk, switch, mux_sel, led0, led_diff, rbb_if, bitbang);
    elsif string_eq(name, "bitbang_cpu")
    then
      work.tb_PicoSoC_bitbang_cpu_pkg.run(cfg, clk, switch, mux_sel, led0, rbb_if, bitbang);
    elsif string_eq(name, "jtag_last")
    then
      work.tb_PicoSoC_jtag_last_pkg.run(cfg, clk, switch, mux_sel, led0, cts_pad, jtag_if, rbb_if, bitbang);
    elsif string_eq(name, "jtag_glitch")
    then
      work.tb_PicoSoC_jtag_glitch_pkg.run(cfg, clk, switch, mux_sel, led0, jtag_if);
    elsif string_eq(name, "trap_cpu0")
    then
      work.tb_PicoSoC_trap_pulse_pkg.run(cfg, 0, clk, switch, inject, led0, led_diff);
    elsif string_eq(name, "trap_cpu1")
    then
      work.tb_PicoSoC_trap_pulse_pkg.run(cfg, 1, clk, switch, inject, led0, led_diff);
    elsif string_eq(name, "trap_reset")
    then
      work.tb_PicoSoC_trap_reset_pkg.run(cfg, clk, switch, mux_sel, inject, led0, led_diff, jtag_if);
    elsif string_eq(name, "trap_tap")
    then
      work.tb_PicoSoC_trap_tap_pkg.run(cfg, clk, switch, mux_sel, inject, led0, led_diff, jtag_if);
    elsif string_eq(name, "hello")
    then
      work.tb_PicoSoC_hello_pkg.run(cfg, led0, led1, led_diff, uart_tx);
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
    elsif string_eq(name, "test_mailbox")
    then
      work.tb_PicoSoC_test_mailbox_pkg.run(cfg, led0, led1, uart_tx);
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
