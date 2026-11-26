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
--              led_diff_o. Every request lasts one SoC clock cycle : the
--              trap of PicoSoC_inject keeps the error until a difference
--              flag of the copy rises. Errors : CPU0 (masked), CPU1 (reset),
--              CPU2 (masked), CPU2 again (its flags already set : no edge,
--              the trap stays pending, no reset), CPU1 (reset ; after it the
--              pending error of CPU2 fires : the first error after the
--              reset, masked, its edge clears the trap), CPU0 (second error
--              after the reset : reset, proves the pending error of CPU2),
--              CPU1 (masked : no trap left pending). During each masked
--              error LED0 still follows the switches (the voter drives the
--              outputs of the two correct CPUs). No TAP in the TMR
--              configurations : the pending trap is checked by its error
--              after the reset, not by INJECT 1 -> 0
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC)
-- 2026-11-23  1.1      mrosiere An error voted out lasts during its checks :
--                               the two other copies drive the bus (vote)
-- 2026-11-26  1.2      mrosiere Requests of one SoC cycle (trap cleared on
--                               the rising edge of a difference flag) ; CPU2
--                               again : the trap stays pending, its error
--                               after the next reset, then CPU0 resets
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
        -- A request of one cycle : the faulty copy is outvoted by the two
        -- others on every output (instruction and data buses)
        inject_error(cpu, cfg, clk, inject);
        wait_cycles (C_SETTLE, clk);
        check_stable(led0    , now - v_start, ERROR, msg & " : no reset of the user SoC (LED0 stable)", C_TB_SCOPE);
        check_value (led_diff, std_logic_vector(to_unsigned(diff, 3)), ERROR, msg & " : led_diff unchanged", C_TB_SCOPE);
        -- The voted CPUs still run the firmware
        set_slv     (not C_SW, clk, switch);
        wait_value  (led0, not C_SW, cfg, msg & " : the firmware runs (LED0 = new switches)");
        set_slv     (C_SW, clk, switch);
        wait_value  (led0, C_SW, cfg, msg & " : the firmware runs (LED0 = switches)");
      end if;
    end procedure;
  begin
    log(ID_SEQUENCER, "fault_tmr : a first error is voted out, a second one resets the user SoC", C_TB_SCOPE);

    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches");
    check_value(led_diff, "000", ERROR, "led_diff : no error yet", C_TB_SCOPE);

    step(0, false, 0, "CPU0, first error"                                              );
    step(1, true , 1, "CPU1, second error"                                             );
    step(2, false, 1, "CPU2, first error after the reset"                              );
    -- The flags of CPU2 are already set : no rising edge, the trap stays
    -- pending (CPU2 keeps its error, voted out), no reset
    step(2, false, 1, "CPU2 again, its flags set : trap pending"                       );
    -- Reset : the pending error of CPU2 fires after it (first error, masked,
    -- its rising edge clears the trap) ...
    step(1, true , 2, "CPU1, second error"                                             );
    wait_cycles (C_SETTLE, clk);
    check_stable(led0, C_SETTLE*cfg.clk_period, ERROR, "pending error of CPU2 after the reset : voted out, no reset (LED0 stable)", C_TB_SCOPE);
    check_value (led_diff, "010", ERROR, "pending error of CPU2 after the reset : led_diff unchanged", C_TB_SCOPE);
    -- ... so an error in CPU0 is the second one after the reset
    step(0, true , 3, "CPU0, second error after the reset (the pending error of CPU2)" );
    -- No trap left pending : a new error in CPU1 is the first one
    step(1, false, 3, "CPU1, first error after the reset"                              );
  end procedure;

end package body tb_PicoSoC_fault_tmr_pkg;
