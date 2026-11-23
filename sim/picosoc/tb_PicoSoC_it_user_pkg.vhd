-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_it_user_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_it_user_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario it_user of tb_PicoSoC, from reset (firmware user*) :
--              the interruption routine increments LED1 on it_user_i
--              (user GIC source 0, level sensitive). Two short pulses give
--              exactly one interruption each, a long pulse at least one;
--              LED1 does not change without interruption. The main loop
--              also prints its loop line and runs the spinlock, mailbox and
--              GIC code of the firmware, it must still copy the switches at
--              the end
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC)
-- 2026-11-23  1.1      mrosiere Loop line at every iteration (esw/user.c)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_it_user_pkg is

  -- LED1 counts the pulses of it_user_i
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   it_user  : out   std_logic
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    );

end package tb_PicoSoC_it_user_pkg;

package body tb_PicoSoC_it_user_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   it_user  : out   std_logic
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ) is
    -- Pulses in clk_i cycles : short = 4 cycles of the SoC clock (one interruption)
    constant C_PULSE_SHORT : positive := 4*cfg.clk_ratio;
    constant C_PULSE_LONG  : positive := 100;
    -- LED1 must not change during C_SETTLE cycles after the interruption
    constant C_SETTLE      : positive := 500*cfg.clk_ratio;
    variable v_led1        : unsigned(led1'length-1 downto 0);
  begin
    log(ID_SEQUENCER, "it_user : the interruption routine increments LED1", C_TB_SCOPE);

    -- The firmware runs its main loop : its setup (GIC, CPU interruptions) is done
    set_slv    (x"A5", clk, switch);
    wait_value (led0, x"A5", cfg, "LED0 = switches : setup done");
    check_value(led1, x"00", ERROR, "LED1 = 0 after reset", C_TB_SCOPE);

    for i in 0 to 2 loop
      v_led1 := unsigned(led1);
      if i < 2
      then
        pulse(C_PULSE_SHORT, cfg.it_on, clk, it_user);
      else
        pulse(C_PULSE_LONG , cfg.it_on, clk, it_user);
      end if;

      if unsigned(led1) = v_led1
      then
        wait until unsigned(led1) /= v_led1 for cfg.timeout;
      end if;
      wait_cycles(C_SETTLE, clk);

      if i < 2
      then
        check_value(unsigned(led1) = v_led1+1, ERROR, "short pulse " & integer'image(i) & " : one interruption, LED1 = 0x" & to_hstring(led1), C_TB_SCOPE);
      else
        check_value(unsigned(led1) > v_led1  , ERROR, "long pulse : at least one interruption, LED1 = 0x" & to_hstring(led1), C_TB_SCOPE);
      end if;

      -- No other interruption
      wait_cycles (C_SETTLE, clk);
      check_stable(led1, C_SETTLE*cfg.clk_period, ERROR, "LED1 unchanged without interruption", C_TB_SCOPE);
    end loop;

    -- The main loop still runs after the interruptions
    set_slv    (x"3C", clk, switch);
    wait_value (led0, x"3C", cfg, "LED0 = switches : the main loop runs after the interruptions");
    check_value(led_diff, "000", ERROR, "led_diff : no difference between the redundant CPUs", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_it_user_pkg;
