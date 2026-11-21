-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_test_pwm_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_test_pwm_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario test_pwm of tb_PicoSoC, from reset (firmware
--              esw/test_pwm.c) : LED0 gives the step of the firmware, the
--              switches acknowledge it
--              * step 1 (configured, disabled) : pwm_o low since the reset
--              * steps 2 and 3 (duty C_DUTY1, then C_DUTY2) : period and
--                high phase of pwm_o
--              * step 4 (disabled) : pwm_o low, until the result line
--                "PASS"
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

package tb_PicoSoC_test_pwm_pkg is

  -- Period and duty cycle of pwm_o
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   pwm      : in    std_logic
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_test_pwm_pkg;

package body tb_PicoSoC_test_pwm_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   pwm      : in    std_logic
    ;signal   uart_tx  : in    std_logic
    ) is
    -- Configuration of esw/test_pwm.c
    constant C_PRESCALER : natural := 3;
    constant C_PERIOD    : natural := 9;
    constant C_DUTY1     : natural := 3;
    constant C_DUTY2     : natural := 7;
    constant C_TICK      : time    := (C_PRESCALER+1) * cfg.clk_period * cfg.clk_ratio;
    variable v_start     : time    := now;

    -- One PWM period from a rising edge of pwm : high phase of duty ticks,
    -- period of C_PERIOD+1 ticks
    procedure check_period
      (constant duty     : in    natural
      ) is
      variable v_rise    : time;
      variable v_fall    : time;
    begin
      await_value(pwm, '0', 0 ns, cfg.timeout, ERROR, "pwm_o low" , C_TB_SCOPE);
      await_value(pwm, '1', 0 ns, cfg.timeout, ERROR, "pwm_o high : start of a period", C_TB_SCOPE);
      v_rise := now;
      await_value(pwm, '0', 0 ns, cfg.timeout, ERROR, "pwm_o low"  , C_TB_SCOPE);
      v_fall := now;
      await_value(pwm, '1', 0 ns, cfg.timeout, ERROR, "pwm_o high : start of the next period", C_TB_SCOPE);
      check_value(v_fall - v_rise, duty         * C_TICK, ERROR, "High phase of " & integer'image(duty) & " ticks", C_TB_SCOPE);
      check_value(now    - v_rise, (C_PERIOD+1) * C_TICK, ERROR, "Period of " & integer'image(C_PERIOD+1) & " ticks", C_TB_SCOPE);
    end procedure;

  begin
    log(ID_SEQUENCER, "test_pwm : period and duty cycle of pwm_o", C_TB_SCOPE);

    -- 1. Configured, still disabled : low since the reset
    wait_value (led0, x"01", cfg, "LED0 = 1 : PWM configured, disabled");
    check_value(pwm, '0', ERROR, "PWM disabled : pwm_o low", C_TB_SCOPE);
    check_stable(pwm, now - v_start, ERROR, "PWM disabled : pwm_o stable since the reset", C_TB_SCOPE);
    set_slv    (x"01", clk, switch);

    -- 2. and 3. Two duty cycles
    wait_value (led0, x"02", cfg, "LED0 = 2 : PWM enabled, first duty");
    check_period(C_DUTY1);
    set_slv    (x"02", clk, switch);

    wait_value (led0, x"03", cfg, "LED0 = 3 : second duty");
    check_period(C_DUTY2);
    set_slv    (x"03", clk, switch);

    -- 4. Disabled : low until the end of the firmware
    wait_value (led0, x"04", cfg, "LED0 = 4 : PWM disabled");
    v_start := now;
    check_value(pwm, '0', ERROR, "PWM disabled : pwm_o low", C_TB_SCOPE);
    wait_pass  ("test_pwm", uart_tx, cfg);
    check_stable(pwm, now - v_start, ERROR, "PWM disabled : pwm_o stays low", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_test_pwm_pkg;
