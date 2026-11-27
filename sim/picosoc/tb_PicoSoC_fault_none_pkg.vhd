-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_fault_none_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_fault_none_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario fault_none of tb_PicoSoC, from reset (firmware
--              user*, supervisor, SAFETY none, fault injection) : an error
--              injected in the only CPU derails the firmware and nothing
--              detects it
--              * a request of one SoC clock cycle on inject_error_i(0) (a
--                short push of the button) : the trap of PicoSoC_inject
--                keeps the error (no difference flag clears it), the bit
--                SEU_BIT(0) of every instruction of the CPU is flipped
--              * the firmware derails : LED0 no longer follows the switches
--              * no copy to compare with : no difference flag, the
--                supervisor does not reset the user SoC and its error
--                counter (led_diff_o) stays 0
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-25  1.0      mrosiere Created
-- 2026-11-27  1.1      mrosiere Request of one SoC cycle (trapped) ; the
--                               firmware derails (LED0 checked)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_fault_none_pkg is

  -- An error in CPU0 : the firmware derails, led_diff stays 0
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    );

end package tb_PicoSoC_fault_none_pkg;

package body tb_PicoSoC_fault_none_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ) is
    constant C_SW1     : std_logic_vector(8-1 downto 0) := x"69";
    constant C_SW2     : std_logic_vector(8-1 downto 0) := x"96";
    -- The firmware copies the switches to LED0 within a few hundred cycles ;
    -- the supervisor would have reset the user SoC within C_SETTLE cycles
    -- (fault_lock_step : a few hundred cycles)
    constant C_SETTLE  : positive := 2000*cfg.clk_ratio;
  begin
    log(ID_SEQUENCER, "fault_none : an error in the only CPU, the firmware derails, the supervisor sees nothing", C_TB_SCOPE);

    set_slv     (C_SW1, clk, switch);
    wait_value  (led0, C_SW1, cfg, "LED0 = switches 0x" & to_hstring(C_SW1));
    check_value (led_diff, "000", ERROR, "led_diff : no error yet", C_TB_SCOPE);

    -- A request of one SoC clock cycle : trapped until the power-on reset
    inject_error(0, cfg, clk, inject);
    set_slv     (C_SW2, clk, switch);
    wait_cycles (C_SETTLE, clk);
    check_value (led0 /= C_SW2, ERROR, "the firmware derails : LED0 (0x" & to_hstring(led0) & ") does not follow the switches 0x" & to_hstring(C_SW2), C_TB_SCOPE);
    check_stable(led_diff, C_SETTLE*cfg.clk_period, ERROR, "led_diff stable after the error : the supervisor did not react", C_TB_SCOPE);
    check_value (led_diff, "000", ERROR, "led_diff = 0 : no difference flag, no reset of the user SoC by the supervisor", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_fault_none_pkg;
