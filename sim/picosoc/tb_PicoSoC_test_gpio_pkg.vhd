-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_test_gpio_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_test_gpio_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario test_gpio of tb_PicoSoC, from reset (firmware
--              esw/test_gpio.c) : pins of the 3 GPIOs of the user SoC
--              * LED0 = 0xA5 and LED1 = 0x5A written by the firmware
--              * switches set to 0x3C (rising edges polled by the
--                firmware), copied into LED0, then cleared (falling edges)
--              * result line "PASS" ; LED1 kept its output value while
--                the firmware read it as an input
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-21  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_test_gpio_pkg is

  -- LEDs written by the firmware, switches read by the firmware
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_test_gpio_pkg;

package body tb_PicoSoC_test_gpio_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    ) is
  begin
    log(ID_SEQUENCER, "test_gpio : LED and switch pins of the GPIOs", C_TB_SCOPE);

    -- Output registers on the pins
    wait_value(led0, x"A5", cfg, "LED0 = 0xA5 (output register)");
    wait_value(led1, x"5A", cfg, "LED1 = 0x5A (output register)");

    -- Rising edges, then the firmware copies the switches into LED0
    set_slv   (x"3C", clk, switch);
    wait_value(led0, x"3C", cfg, "LED0 = switches 0x3C");

    -- Falling edges
    set_slv   (x"00", clk, switch);

    wait_pass  ("test_gpio", uart_tx, cfg);
    check_value(led1, x"5A", ERROR, "LED1 pins = output register 0x5A (data_oe only changes the read)", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_test_gpio_pkg;
