-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_test_timer_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_test_timer_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario test_timer of tb_PicoSoC, from reset (firmware
--              esw/test_timer.c) : LED0 counts the interrupts of the timer
--              (periodic, C_PERIOD cycles of the SoC clock)
--              * time between the counts 1, 2, 3 and 4 : C_PERIOD cycles,
--                within the interrupt latency (C_JITTER cycles)
--              * result line "PASS", then LED0 stays at 4 (timer stopped)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-21  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_test_timer_pkg is

  -- Period of the timer seen on LED0
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   led0     : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_test_timer_pkg;

package body tb_PicoSoC_test_timer_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   led0     : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    ) is
    constant C_PERIOD  : positive := 2000; -- SoC clock cycles (TIMER_PERIOD of esw/test_timer.c)
    constant C_JITTER  : positive := 10;   -- latency difference of two interrupts (SoC clock cycles)
    constant C_NB      : positive := 4;    -- periods counted by the firmware
    constant C_CYCLE   : time     := cfg.clk_period * cfg.clk_ratio;
    variable v_last    : time;
  begin
    log(ID_SEQUENCER, "test_timer : period of " & integer'image(C_PERIOD) & " SoC cycles on LED0", C_TB_SCOPE);

    wait_value(led0, x"01", cfg, "LED0 = 1 : first period");
    v_last := now;
    for i in 2 to C_NB loop
      wait_value(led0, std_logic_vector(to_unsigned(i, 8)), cfg, "LED0 = " & integer'image(i));
      check_value_in_range(now - v_last, (C_PERIOD-C_JITTER)*C_CYCLE, (C_PERIOD+C_JITTER)*C_CYCLE, ERROR,
                           "Timer period " & integer'image(i-1), C_TB_SCOPE);
      v_last := now;
    end loop;

    -- Timer stopped by the firmware : no more interrupt
    wait_pass  ("test_timer", uart_tx, cfg);
    wait for 2*C_PERIOD*C_CYCLE;
    check_stable(led0, now - v_last, ERROR, "LED0 stays at 4 : timer stopped", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_test_timer_pkg;
