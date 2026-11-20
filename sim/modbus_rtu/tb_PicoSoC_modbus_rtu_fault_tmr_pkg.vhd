-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_modbus_rtu_fault_tmr_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_modbus_rtu_fault_tmr_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario fault_tmr of tb_PicoSoC_modbus_rtu, from reset
--              (supervisor, TMR, fault injection) : a first error is voted
--              out (LED0 kept), a second error resets the user SoC (LED0
--              back to 0)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC_modbus_rtu)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_modbus_rtu_bfm_pkg.all;

package tb_PicoSoC_modbus_rtu_fault_tmr_pkg is

  -- A first error is voted out, a second one resets the user SoC
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    );

end package tb_PicoSoC_modbus_rtu_fault_tmr_pkg;

package body tb_PicoSoC_modbus_rtu_fault_tmr_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ) is
  begin
    log(ID_SEQUENCER, "fault_tmr : a first error is voted out, a second one resets the user SoC", C_TB_SCOPE);

    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA, x"CA", "Write LED0 Data <= 0xCA", cfg, uart_rx, uart_tx);
    check_led0  (led0, x"CA", "LED0 <= 0xCA", cfg);

    check_led_diff(led_diff, 0, "led_diff = 0 (no reset yet)");
    inject_error(0, cfg, inject);
    check_led0  (led0, x"CA", "LED0 = 0xCA (CPU0, first error : no reset)", cfg);

    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA, x"FE", "Write LED0 Data <= 0xFE", cfg, uart_rx, uart_tx);
    check_led0  (led0, x"FE", "LED0 <= 0xFE", cfg);

    inject_error(1, cfg, inject);
    check_led0  (led0, x"00", "LED0 <= 0x00 after reset (CPU1, second error)", cfg);
    check_led_diff(led_diff, 1, "led_diff = 1 (resets of the user SoC)");

    wait for C_RESET_LATENCY;
    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA, x"ED", "Write LED0 Data <= 0xED", cfg, uart_rx, uart_tx);
    check_led0  (led0, x"ED", "LED0 <= 0xED", cfg);

    inject_error(2, cfg, inject);
    check_led0  (led0, x"ED", "LED0 = 0xED (CPU2, first error : no reset)", cfg);

    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA, x"5E", "Write LED0 Data <= 0x5E", cfg, uart_rx, uart_tx);
    check_led0  (led0, x"5E", "LED0 <= 0x5E (CPU2 voted out)", cfg);

    inject_error(0, cfg, inject);
    check_led0  (led0, x"00", "LED0 <= 0x00 after reset (CPU0, second error)", cfg);
    check_led_diff(led_diff, 2, "led_diff = 2 (resets of the user SoC)");

    wait for C_RESET_LATENCY;
    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA, x"21", "Write LED0 Data <= 0x21", cfg, uart_rx, uart_tx);
    check_led0  (led0, x"21", "LED0 <= 0x21", cfg);

    inject_error(1, cfg, inject);
    check_led0  (led0, x"21", "LED0 = 0x21 (CPU1, first error : no reset)", cfg);

    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA, x"04", "Write LED0 Data <= 0x04", cfg, uart_rx, uart_tx);
    check_led0  (led0, x"04", "LED0 <= 0x04", cfg);

    inject_error(2, cfg, inject);
    check_led0  (led0, x"00", "LED0 <= 0x00 after reset (CPU2, second error)", cfg);
    check_led_diff(led_diff, 3, "led_diff = 3 (resets of the user SoC)");
  end procedure;

end package body tb_PicoSoC_modbus_rtu_fault_tmr_pkg;
