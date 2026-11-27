-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_fault_tmr_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_fault_tmr_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario fault_tmr of tb_PicoSoC, from reset (firmware
--              user_loop, supervisor -DSAFETY_TMR, TMR, fault injection) :
--              requests of one SoC clock cycle (the trap keeps the error
--              until a difference flag of the copy rises)
--              * CPU0 : voted out, no reset : the lines go on in sequence,
--                led_diff_o = 0
--              * CPU1 : second error, the supervisor resets the user SoC
--                (led_diff_o = 1), the sequence restarts from the loop 0
--              * CPU2 : first error after the reset, voted out
--              * CPU0 : second error, reset (led_diff_o = 2), restart
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created
-- 2026-11-27  1.1      mrosiere Firmware user_loop : the lines go on after a
--                               voted error, restart after a reset
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_sequence_pkg.all;

package tb_PicoSoC_fault_tmr_pkg is

  -- TMR : a first error voted out, a second one resets the user SoC
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_fault_tmr_pkg;

package body tb_PicoSoC_fault_tmr_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    ) is
    variable v_next    : natural := 2;   -- loop number of the next line
  begin
    log(ID_SEQUENCER, "fault_tmr : a first error is voted out, a second one resets the user SoC", C_TB_SCOPE);

    check_lines(0, 2, "before the errors", uart_tx, cfg);
    check_value(led_diff, "000", ERROR, "led_diff : no error yet", C_TB_SCOPE);

    -- CPU0 : voted out
    inject_error(0, cfg, clk, inject);
    check_lines (v_next, 3, "error in CPU0, voted out : the lines go on", uart_tx, cfg);
    check_value (led_diff, "000", ERROR, "error in CPU0 : no reset", C_TB_SCOPE);

    -- CPU1 : second error, reset
    inject_error (1, cfg, clk, inject);
    wait_value   (led_diff, "001", cfg, "error in CPU1 : second error, reset of the user SoC (led_diff = 1)");
    check_restart(2, "error in CPU1", uart_tx, cfg);
    v_next := 3;

    -- CPU2 : first error after the reset, voted out
    inject_error(2, cfg, clk, inject);
    check_lines (v_next, 3, "error in CPU2, voted out : the lines go on", uart_tx, cfg);
    check_value (led_diff, "001", ERROR, "error in CPU2 : no reset", C_TB_SCOPE);

    -- CPU0 : second error, reset
    inject_error (0, cfg, clk, inject);
    wait_value   (led_diff, "010", cfg, "error in CPU0 : second error, reset of the user SoC (led_diff = 2)");
    check_restart(2, "error in CPU0", uart_tx, cfg);
    check_value  (led_diff, "010", ERROR, "led_diff = 2 : one reset per second error", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_fault_tmr_pkg;
