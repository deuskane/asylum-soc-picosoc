-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_test_uart_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_test_uart_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario test_uart of tb_PicoSoC, from reset (firmware
--              esw/test/test_uart.c) : uart_tx_o and uart_rx_i of the UART
--              * '>' then 0x5A sent : read by polling
--              * '>' then 0xA5 sent : read by the interrupt routine (UART
--                source of the user GIC), copied into LED0, one interrupt
--                counted on LED1
--              * result line "PASS"
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

package tb_PicoSoC_test_uart_pkg is

  -- Bytes sent to the firmware on its prompts
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_test_uart_pkg;

package body tb_PicoSoC_test_uart_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ) is
  begin
    log(ID_SEQUENCER, "test_uart : TX and RX pins, RX polled then by interrupt", C_TB_SCOPE);

    uart_check(x"3E", "Prompt '>' : RX polled", uart_tx, cfg);
    uart_send (x"5A", "Byte read by polling"  , uart_rx, cfg);

    uart_check(x"3E", "Prompt '>' : RX interrupt", uart_tx, cfg);
    uart_send (x"A5", "Byte read by the interrupt routine", uart_rx, cfg);

    wait_pass  ("test_uart", uart_tx, cfg);
    check_value(led0, x"A5", ERROR, "LED0 = byte read by the interrupt routine", C_TB_SCOPE);
    check_value(led1, x"01", ERROR, "LED1 = one interrupt", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_test_uart_pkg;
