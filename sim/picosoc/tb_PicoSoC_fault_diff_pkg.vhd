-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_fault_diff_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_fault_diff_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario fault_diff of tb_PicoSoC, from reset (firmware user*,
--              no supervisor, lock-step or TMR, fault injection) : without
--              supervisor, led_diff_o shows the difference flags. An error
--              injected in CPU0 sets the flags of CPU0 (lock-step : 001,
--              TMR : CPU0 vs CPU1 and CPU2 vs CPU0, 101) and they stay set
--              (sticky until the reset)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_fault_diff_pkg is

  -- Difference flags of an error in CPU0, sticky
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    );

end package tb_PicoSoC_fault_diff_pkg;

package body tb_PicoSoC_fault_diff_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ) is
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"5A";
    -- The flags stay set during C_SETTLE cycles after the error
    constant C_SETTLE  : positive := 2000*cfg.clk_ratio;
    variable v_diff    : std_logic_vector(3-1 downto 0);
  begin
    log(ID_SEQUENCER, "fault_diff : difference flags of an error in CPU0 on led_diff_o", C_TB_SCOPE);

    v_diff := "101" when cfg.tmr else "001";

    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches");
    check_value(led_diff, "000", ERROR, "led_diff : no difference before the error", C_TB_SCOPE);

    inject_error(0, cfg, clk, inject);
    wait_value  (led_diff, v_diff, cfg, "led_diff : difference flags of CPU0");
    wait_cycles (C_SETTLE, clk);
    check_stable(led_diff, C_SETTLE*cfg.clk_period, ERROR, "led_diff : the flags are sticky", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_fault_diff_pkg;
