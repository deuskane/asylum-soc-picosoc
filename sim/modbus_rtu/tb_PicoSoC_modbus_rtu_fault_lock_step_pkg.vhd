-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_modbus_rtu_fault_lock_step_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_modbus_rtu_fault_lock_step_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario fault_lock_step of tb_PicoSoC_modbus_rtu, from reset
--              (supervisor, lock-step, fault injection) : an error in CPU0,
--              then in CPU1, resets the user SoC (LED0 back to 0)
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

package tb_PicoSoC_modbus_rtu_fault_lock_step_pkg is

  -- Each error resets the user SoC
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    );

end package tb_PicoSoC_modbus_rtu_fault_lock_step_pkg;

package body tb_PicoSoC_modbus_rtu_fault_lock_step_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ) is
  begin
    log(ID_SEQUENCER, "fault_lock_step : each error resets the user SoC (LED0 = 0)", C_TB_SCOPE);

    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA, x"DE", "Write LED0 Data <= 0xDE", cfg, uart_rx, uart_tx);
    check_led0  (led0, x"DE", "LED0 <= 0xDE", cfg);

    check_led_diff(led_diff, 0, "led_diff = 0 (no reset yet)");
    inject_error(0, cfg, inject);
    check_led0  (led0, x"00", "LED0 <= 0x00 after reset (CPU0)", cfg);
    check_led_diff(led_diff, 1, "led_diff = 1 (resets of the user SoC)");

    wait for C_RESET_LATENCY;
    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA, x"AD", "Write LED0 Data <= 0xAD", cfg, uart_rx, uart_tx);
    check_led0  (led0, x"AD", "LED0 <= 0xAD", cfg);

    inject_error(1, cfg, inject);
    check_led0  (led0, x"00", "LED0 <= 0x00 after reset (CPU1)", cfg);
    check_led_diff(led_diff, 2, "led_diff = 2 (resets of the user SoC)");
  end procedure;

end package body tb_PicoSoC_modbus_rtu_fault_lock_step_pkg;
