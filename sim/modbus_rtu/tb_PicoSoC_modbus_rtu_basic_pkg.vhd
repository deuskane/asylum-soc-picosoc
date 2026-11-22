-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_modbus_rtu_basic_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_modbus_rtu_basic_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario basic of tb_PicoSoC_modbus_rtu, from reset : LED0
--              written and read back, switches read, a frame to another
--              slave id ignored, broadcast write (slave id 0x00)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC_modbus_rtu)
-- 2026-11-22  1.1      mrosiere Switches 0xDA (was 0x5A : MSBs 01 give the
--                               UART pads to the HWLA UART)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_modbus_rtu_bfm_pkg.all;

package tb_PicoSoC_modbus_rtu_basic_pkg is

  -- LED0 and switches through Modbus, slave id filter
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    );

end package tb_PicoSoC_modbus_rtu_basic_pkg;

package body tb_PicoSoC_modbus_rtu_basic_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ) is
  begin
    log(ID_SEQUENCER, "basic : LED0 written and read, switches read, slave id", C_TB_SCOPE);

    -- Write LED0 and check if led switch have the expected value
    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA  ,x"21",        "Write LED0 Data <= 0x21", cfg, uart_rx, uart_tx);
    check_led0  (led0, x"21", "LED0 <= 0x21", cfg);

    -- Read LED0 and check if it's the expected value
    wait for C_FRAME_GAP;
    modbus_read (C_LED0_DATA  ,(0 => x"21"), "Read  LED0 Data", cfg, uart_rx, uart_tx);

    -- Change Switch and check if it's the expected value
    wait for C_FRAME_GAP;
    switch <= x"DA";
    modbus_read (C_SWITCH_DATA,(0 => x"DA"), "Read  SWITCH Data", cfg, uart_rx, uart_tx);

    wait for C_FRAME_GAP;
    switch <= x"3C";
    modbus_read (C_SWITCH_DATA,(0 => x"3C"), "Read  SWITCH Data", cfg, uart_rx, uart_tx);

    wait for C_FRAME_GAP;
    switch <= x"1E";
    modbus_read (C_SWITCH_DATA,(0 => x"1E"), "Read  SWITCH Data", cfg, uart_rx, uart_tx);

    -- Write LED0 with another ID and check that the LED0 don't change
    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA  ,x"23",        "Write LED0 Data <= 0x23, with another ID", cfg, uart_rx, uart_tx, not C_MODBUS_SLAVE_ID);
    check_led0  (led0, x"21", "LED0 = 0x21 (other slave id ignored)", cfg);

    -- Read LED0 data and data_oe
    wait for C_FRAME_GAP;
    modbus_read (C_LED0_DATA  ,(0 => x"21",
                                1 => x"FF"), "Read  LED0 Data & OE", cfg, uart_rx, uart_tx);
    check_led0  (led0, x"21", "LED0 = 0x21", cfg);

    -- Write LED0 with broadcast Address and check that the LED0 change
    wait for C_FRAME_GAP;
    modbus_write(C_LED0_DATA  ,x"15",        "Write LED0 Data <= 0x15, with broadcast address", cfg, uart_rx, uart_tx, x"00");
    check_led0  (led0, x"15", "LED0 <= 0x15", cfg);

    wait for C_FRAME_GAP;
    modbus_read (C_LED0_DATA  ,(0 => x"15"), "Read  LED0 Data", cfg, uart_rx, uart_tx);
  end procedure;

end package body tb_PicoSoC_modbus_rtu_basic_pkg;
