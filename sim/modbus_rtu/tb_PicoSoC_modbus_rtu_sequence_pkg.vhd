-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_modbus_rtu_sequence_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_modbus_rtu_sequence_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario sequence of tb_PicoSoC_modbus_rtu, from reset :
--              each switch alone read through Modbus, then written into LED0;
--              the two MSBs together (01 and 10 give the UART pads to the
--              HWLA UART and to JTAG)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC_modbus_rtu)
-- 2026-11-22  1.1      mrosiere The two MSBs together (UART pads)
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

    for i in 0 to 6 loop
      v_sw    := (others => '0');
      v_sw(i) := '1';
      -- MSBs 01 or 10 : the UART pads would leave the user UART
      if i = 6
      then
        v_sw(7) := '1';
      end if;
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
