-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_fault_lock_step_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_fault_lock_step_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario fault_lock_step of tb_PicoSoC, from reset (firmware
--              user*, supervisor, lock-step, fault injection) : an error
--              injected in CPU0 or CPU1 (instruction bit flipped) is detected
--              by the lock-step compare; the supervisor resets the user SoC
--              (LED0 back to 0, then the switches again) and counts the
--              errors on led_diff_o. Errors in CPU0, CPU1, then CPU0 again;
--              one reset per error (LED0 and led_diff stable at the end)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_fault_lock_step_pkg is

  -- Each error resets the user SoC and increments led_diff
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    );

end package tb_PicoSoC_fault_lock_step_pkg;

package body tb_PicoSoC_fault_lock_step_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ) is
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"96";
    type     t_cpus    is array (natural range <>) of natural;
    constant C_CPUS    : t_cpus := (0, 1, 0);
    -- One reset per error : LED0 and led_diff stable during C_SETTLE cycles
    constant C_SETTLE  : positive := 2000*cfg.clk_ratio;
  begin
    log(ID_SEQUENCER, "fault_lock_step : the supervisor resets the user SoC on each error", C_TB_SCOPE);

    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches");
    check_value(led_diff, "000", ERROR, "led_diff : no error yet", C_TB_SCOPE);

    for i in C_CPUS'range loop
      inject_error(C_CPUS(i), cfg, clk, inject);
      wait_value(led0    , x"00", cfg, "error " & integer'image(i+1) & " in CPU" & integer'image(C_CPUS(i)) & " : user SoC reset (LED0 = 0)");
      wait_value(led0    , C_SW , cfg, "error " & integer'image(i+1) & " : the firmware runs again (LED0 = switches)");
      wait_value(led_diff, std_logic_vector(to_unsigned(i+1, 3)), cfg, "error " & integer'image(i+1) & " : led_diff = number of errors");
    end loop;

    wait_cycles (C_SETTLE, clk);
    check_stable(led0    , C_SETTLE*cfg.clk_period, ERROR, "LED0 stable : one reset per error", C_TB_SCOPE);
    check_value (led_diff, std_logic_vector(to_unsigned(C_CPUS'length, 3)), ERROR, "led_diff = number of errors", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_fault_lock_step_pkg;
