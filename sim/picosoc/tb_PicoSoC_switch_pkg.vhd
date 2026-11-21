-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_switch_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_switch_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario switch of tb_PicoSoC, from reset : the firmware
--              copies the switches into LED0 (every firmware but hello).
--              Switches set one by one from bit 7 down to bit 0, then
--              0x5A and 0xA5; no difference between the redundant CPUs
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_switch_pkg is

  -- LED0 follows the switches, led_diff stays 0
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    );

end package tb_PicoSoC_switch_pkg;

package body tb_PicoSoC_switch_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ) is
    variable v_sw      : std_logic_vector(8-1 downto 0) := (others => '0');
  begin
    log(ID_SEQUENCER, "switch : LED0 follows the switches", C_TB_SCOPE);
    for i in 8-1 downto 0 loop
      v_sw(i) := '1';
      set_slv   (v_sw, clk, switch);
      wait_value(led0, v_sw, cfg, "LED0 = switches 0x" & to_hstring(v_sw));
    end loop;

    for i in 0 to 1 loop
      v_sw := x"5A" when i = 0 else x"A5";
      set_slv   (v_sw, clk, switch);
      wait_value(led0, v_sw, cfg, "LED0 = switches 0x" & to_hstring(v_sw));
    end loop;

    check_value(led_diff, "000", ERROR, "led_diff : no difference between the redundant CPUs", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_switch_pkg;
