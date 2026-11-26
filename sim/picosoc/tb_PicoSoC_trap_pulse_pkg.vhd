-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_trap_pulse_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_trap_pulse_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenarios trap_cpu0 and trap_cpu1 of tb_PicoSoC, from reset
--              (firmware user*, supervisor, lock-step, fault injection) : a
--              request of one SoC clock cycle on inject_error_i sets the trap
--              of the copy (PicoSoC_inject), which flips its instruction bit
--              until the compare flags it (diff(0), CPU0 vs CPU1, for both
--              copies) : the supervisor resets the user SoC once and counts
--              it ; the trap is then cleared : no other reset (LED0 and
--              led_diff_o stable). Twice
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-26  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_trap_pulse_pkg is

  -- Requests of one SoC clock cycle in the copy cpu (0 or 1)
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;constant cpu      : in    natural
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    );

end package tb_PicoSoC_trap_pulse_pkg;

package body tb_PicoSoC_trap_pulse_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;constant cpu      : in    natural
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ) is
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"C3";
    -- One reset per request : LED0 and led_diff stable during C_SETTLE cycles
    constant C_SETTLE  : positive := 2000*cfg.clk_ratio;
  begin
    log(ID_SEQUENCER, "trap_cpu" & integer'image(cpu) & " : a request of one cycle, one reset", C_TB_SCOPE);

    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches");
    check_value(led_diff, "000", ERROR, "led_diff : no error yet", C_TB_SCOPE);

    for i in 1 to 2 loop
      -- One cycle of the SoC clock (clk_ratio cycles of clk_i)
      log(ID_SEQUENCER_SUB, "Request of one SoC clock cycle in CPU" & integer'image(cpu), C_TB_SCOPE);
      wait until falling_edge(clk);
      inject(cpu) <= cfg.fault_on;
      for c in 1 to cfg.clk_ratio loop
        wait until falling_edge(clk);
      end loop;
      inject(cpu) <= not cfg.fault_on;

      wait_value  (led0    , x"00", cfg, "request " & integer'image(i) & " : trapped until the compare flags it, user SoC reset (LED0 = 0)");
      wait_value  (led0    , C_SW , cfg, "request " & integer'image(i) & " : the firmware runs again (LED0 = switches)");
      wait_value  (led_diff, std_logic_vector(to_unsigned(i, 3)), cfg, "request " & integer'image(i) & " : led_diff = number of resets");
      wait_cycles (C_SETTLE, clk);
      check_stable(led0    , C_SETTLE*cfg.clk_period, ERROR, "request " & integer'image(i) & " : trap cleared, LED0 stable", C_TB_SCOPE);
      check_value (led_diff, std_logic_vector(to_unsigned(i, 3)), ERROR, "request " & integer'image(i) & " : trap cleared, one reset", C_TB_SCOPE);
    end loop;
  end procedure;

end package body tb_PicoSoC_trap_pulse_pkg;
