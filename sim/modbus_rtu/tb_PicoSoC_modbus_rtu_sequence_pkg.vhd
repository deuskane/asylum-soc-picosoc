-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_modbus_rtu_sequence_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_modbus_rtu_sequence_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario sequence of tb_PicoSoC_modbus_rtu, from reset :
--              each switch alone read through Modbus, then written into LED0,
--              but the two MSBs : they select the function of the UART pads
--              (only 00 keeps the user UART : 01 HWLA UART, 10 JTAG, 11 JTAG
--              over the UART)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC_modbus_rtu)
-- 2026-11-22  1.1      mrosiere The two MSBs together (UART pads)
-- 2026-11-23  1.2      mrosiere Switches 0 to 5 only (MSBs 11 : JTAG over the
--                               UART pads)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_modbus_rtu_bfm_pkg.all;

package tb_PicoSoC_modbus_rtu_sequence_pkg is

  -- Each switch read, then written into LED0 (the two MSBs together)
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    );

end package tb_PicoSoC_modbus_rtu_sequence_pkg;

package body tb_PicoSoC_modbus_rtu_sequence_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ) is
    variable v_sw      : std_logic_vector(8-1 downto 0);
  begin
    log(ID_SEQUENCER, "sequence : each switch alone read, then written into LED0", C_TB_SCOPE);

    -- The MSBs (6 and 7) stay 00 : the UART pads would leave the user UART
    for i in 0 to 5 loop
      v_sw    := (others => '0');
      v_sw(i) := '1';
      wait for C_FRAME_GAP;
      switch  <= v_sw;
      wait for C_FRAME_GAP;
      modbus_read (C_SWITCH_DATA,(0 => v_sw), "Read  SWITCH Data - 0x" & to_hstring(v_sw), cfg, uart_rx, uart_tx);
      wait for C_FRAME_GAP;
      modbus_write(C_LED0_DATA  ,v_sw       , "Write LED0 Data - 0x" & to_hstring(v_sw), cfg, uart_rx, uart_tx);
      check_led0  (led0, v_sw, "LED0 <= 0x" & to_hstring(v_sw), cfg);
    end loop;
  end procedure;

end package body tb_PicoSoC_modbus_rtu_sequence_pkg;
