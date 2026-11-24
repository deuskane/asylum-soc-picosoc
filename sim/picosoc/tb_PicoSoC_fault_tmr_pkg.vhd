-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_fault_tmr_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_fault_tmr_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario fault_tmr of tb_PicoSoC, from reset (firmware user*,
--              supervisor with esw/system/supervisor.c -DSAFETY_TMR, TMR, fault
--              injection) : the voter masks a first error (the supervisor
--              only masks its difference lines, no reset); a second error on
--              a line still unmasked resets the user SoC and increments
--              led_diff_o. Errors : CPU0 (masked), CPU1 (reset), CPU2
--              (masked), CPU2 (lines already masked), CPU1 (reset), CPU1
--              (masked). During each masked error, kept active while it is
--              checked, LED0 still follows the switches (the voter drives
--              the outputs of the two correct CPUs)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC)
-- 2026-11-23  1.1      mrosiere An error voted out lasts during its checks :
--                               the two other copies drive the bus (vote)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_fault_tmr_pkg is

  -- A first error is voted out, a second one resets the user SoC
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    );

end package tb_PicoSoC_fault_tmr_pkg;

package body tb_PicoSoC_fault_tmr_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ) is
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"69";
    -- No reset : LED0 and led_diff stable during C_SETTLE cycles after the error
    constant C_SETTLE  : positive := 2000*cfg.clk_ratio;

    -- Error in cpu : reset of the user SoC or not, led_diff after the error
    procedure step
      (constant cpu      : in natural
      ;constant reset    : in boolean
      ;constant diff     : in natural
      ;constant msg      : in string
      ) is
      variable v_start   : time;
    begin
      v_start := now;
      if reset
      then
        inject_error(cpu, cfg, clk, inject);
        wait_value(led0    , x"00", cfg, msg & " : user SoC reset (LED0 = 0)");
        wait_value(led0    , C_SW , cfg, msg & " : the firmware runs again (LED0 = switches)");
        wait_value(led_diff, std_logic_vector(to_unsigned(diff, 3)), cfg, msg & " : led_diff = number of resets");
      else
        -- The error lasts during the checks : the faulty copy is outvoted
        -- by the two others on every output (instruction and data buses)
        log(ID_SEQUENCER_SUB, "Inject an error in CPU" & integer'image(cpu) & " during the checks", C_TB_SCOPE);
        wait until falling_edge(clk);
        inject(cpu) <= cfg.fault_on;
        wait_cycles (C_SETTLE, clk);
        check_stable(led0    , now - v_start, ERROR, msg & " : no reset of the user SoC (LED0 stable)", C_TB_SCOPE);
        check_value (led_diff, std_logic_vector(to_unsigned(diff, 3)), ERROR, msg & " : led_diff unchanged", C_TB_SCOPE);
        -- The voted CPUs still run the firmware
        set_slv     (not C_SW, clk, switch);
        wait_value  (led0, not C_SW, cfg, msg & " : the firmware runs (LED0 = new switches)");
        set_slv     (C_SW, clk, switch);
        wait_value  (led0, C_SW, cfg, msg & " : the firmware runs (LED0 = switches)");
        wait until falling_edge(clk);
        inject(cpu) <= not cfg.fault_on;
      end if;
    end procedure;
  begin
    log(ID_SEQUENCER, "fault_tmr : a first error is voted out, a second one resets the user SoC", C_TB_SCOPE);

    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches");
    check_value(led_diff, "000", ERROR, "led_diff : no error yet", C_TB_SCOPE);

    step(0, false, 0, "CPU0, first error"                       );
    step(1, true , 1, "CPU1, second error"                      );
    step(2, false, 1, "CPU2, first error after the reset"       );
    step(2, false, 1, "CPU2 again, its difference lines masked" );
    step(1, true , 2, "CPU1, second error"                      );
    step(1, false, 2, "CPU1, first error after the reset"       );
  end procedure;

end package body tb_PicoSoC_fault_tmr_pkg;
