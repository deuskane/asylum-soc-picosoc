-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_modbus_rtu_tests_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_modbus_rtu_tests_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenarios of tb_PicoSoC_modbus_rtu : names (valid items of
--              TESTS_LIST), configurations where each one applies, and
--              dispatch (run_test) to the package of each scenario
--              (tb_PicoSoC_modbus_rtu_<name>_pkg)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC_modbus_rtu)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum;
use     asylum.string_pkg.all;

library work;
use     work.tb_PicoSoC_modbus_rtu_bfm_pkg.all;

package tb_PicoSoC_modbus_rtu_tests_pkg is

  -- Names of the scenarios (valid items of TESTS_LIST)
  constant C_TESTS : string := "basic,fault_lock_step,fault_tmr,sequence";

  -- True when the scenario name applies to the configuration
  function test_applies
    (name       : string
    ;supervisor : boolean
    ;safety     : string
    ;fault      : boolean
    ) return boolean;

  -- Run the scenario name
  procedure run_test
    (constant name     : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    );

end package tb_PicoSoC_modbus_rtu_tests_pkg;

package body tb_PicoSoC_modbus_rtu_tests_pkg is

  function test_applies
    (name       : string
    ;supervisor : boolean
    ;safety     : string
    ;fault      : boolean
    ) return boolean is
  begin
    if    string_eq(name, "fault_lock_step") then return supervisor and fault and string_eq(safety, "lock-step");
    elsif string_eq(name, "fault_tmr"      ) then return supervisor and fault and string_eq(safety, "tmr");
    else                                          return list_contains(C_TESTS, name);
    end if;
  end function;

  procedure run_test
    (constant name     : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ) is
  begin
    if    string_eq(name, "basic")
    then
      work.tb_PicoSoC_modbus_rtu_basic_pkg.run(cfg, uart_rx, uart_tx, switch, led0);
    elsif string_eq(name, "fault_lock_step")
    then
      work.tb_PicoSoC_modbus_rtu_fault_lock_step_pkg.run(cfg, uart_rx, uart_tx, inject, led0, led_diff);
    elsif string_eq(name, "fault_tmr")
    then
      work.tb_PicoSoC_modbus_rtu_fault_tmr_pkg.run(cfg, uart_rx, uart_tx, inject, led0, led_diff);
    elsif string_eq(name, "sequence")
    then
      work.tb_PicoSoC_modbus_rtu_sequence_pkg.run(cfg, uart_rx, uart_tx, switch, led0);
    else
      alert(TB_ERROR, "Unknown test " & name, C_TB_SCOPE);
    end if;
  end procedure;

end package body tb_PicoSoC_modbus_rtu_tests_pkg;
