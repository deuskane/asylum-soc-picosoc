-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_fault_lock_step_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_fault_lock_step_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario fault_lock_step of tb_PicoSoC, from reset
--              (firmware user_loop, supervisor, lock-step, fault
--              injection) : errors in CPU0, CPU1, CPU0 (requests of one
--              SoC clock cycle, trapped until the compare flags the copy).
--              After each one the supervisor resets the user SoC once
--              (led_diff_o counts the errors) and the firmware prints the
--              xorwow sequence again from the loop 0
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created
-- 2026-11-27  1.1      mrosiere Firmware user_loop : the restart of the
--                               sequence after each reset
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_sequence_pkg.all;

package tb_PicoSoC_fault_lock_step_pkg is

  -- Each error resets the user SoC and increments led_diff
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_fault_lock_step_pkg;

package body tb_PicoSoC_fault_lock_step_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    ) is
    type     t_cpus    is array (natural range <>) of natural;
    constant C_CPUS    : t_cpus := (0, 1, 0);
  begin
    log(ID_SEQUENCER, "fault_lock_step : the supervisor resets the user SoC on each error", C_TB_SCOPE);

    check_lines(0, 2, "before the errors", uart_tx, cfg);
    check_value(led_diff, "000", ERROR, "led_diff : no error yet", C_TB_SCOPE);

    for i in C_CPUS'range loop
      inject_error (C_CPUS(i), cfg, clk, inject);
      wait_value   (led_diff, std_logic_vector(to_unsigned(i+1, 3)), cfg, "error " & integer'image(i+1) & " in CPU" & integer'image(C_CPUS(i)) & " : led_diff = number of errors");
      check_restart(3, "error " & integer'image(i+1), uart_tx, cfg);
    end loop;

    check_value(led_diff, std_logic_vector(to_unsigned(C_CPUS'length, 3)), ERROR, "led_diff = number of errors : one reset per error", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_fault_lock_step_pkg;
