-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_test_gic_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_test_gic_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario test_gic of tb_PicoSoC, from reset (firmware
--              esw/test/test_gic.c) : one it_user_i pulse on each request of
--              the firmware (LED0 = 1, 2, 3)
--              * pulse 1 : masked, no interrupt (LED1 = 0)
--              * pulse 2 : masked, taken when unmasked (LED1 = 1)
--              * pulse 3 : taken at once (LED1 = 2)
--              * result line "PASS", LED1 = 2 interrupts
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

package tb_PicoSoC_test_gic_pkg is

  -- it_user_i pulses requested by the firmware
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   it_user  : out   std_logic
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_test_gic_pkg;

package body tb_PicoSoC_test_gic_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   it_user  : out   std_logic
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    ) is
  begin
    log(ID_SEQUENCER, "test_gic : it_user_i masked, pending and taken", C_TB_SCOPE);

    for i in 1 to 3 loop
      wait_value(led0, std_logic_vector(to_unsigned(i, 8)), cfg, "LED0 = " & integer'image(i) & " : request of pulse " & integer'image(i));
      -- Short pulse (4 SoC cycles) : the GIC records the event
      pulse(4*cfg.clk_ratio, cfg.it_on, clk, it_user);
    end loop;

    wait_pass  ("test_gic", uart_tx, cfg);
    check_value(led1, x"02", ERROR, "LED1 = 2 interrupts (pulses 2 and 3)", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_test_gic_pkg;
