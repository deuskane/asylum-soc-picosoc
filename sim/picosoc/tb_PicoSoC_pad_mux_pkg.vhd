-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_pad_mux_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_pad_mux_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario pad_mux of tb_PicoSoC, from reset (firmware
--              user_uart*) : the two MSBs of the switches give the 4 UART
--              pads to one function
--              * 00 : user UART (banner, echo of a byte), RTS* driven,
--                CTS* not driven by the SoC
--              * 11 : user UART (echo of a byte), RTS* driven
--              * 01 : HWLA UART : the loop lines of the firmware (switch(5))
--                do not reach the TX pad, which stays idle ; the firmware
--                does not wait on CTS* (LED0 follows the switches) ; CTS*
--                and RTS* not driven
--              * 10 : JTAG : no pad driven out of a scan (TDI, TMS : inputs,
--                TDO : not driven), the firmware does not wait on CTS*
--              * back to 00 : the loop lines are on the TX pad again
--              * 01, with DEBUG_ENABLE and fault injection : an error in
--                CPU0 triggers the HWLA, its capture is on the TX pad, bit by
--                bit equal to debug_uart_tx_o
--              Pull-ups of the tb : a pad driven by nobody is 'H' ; cts_b is
--              the CTS* of the cable ('Z' : released)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-22  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_pad_mux_pkg is

  -- Each code of the switch MSBs
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   cts_b    : out   std_logic
    ;signal   cts_pad  : in    std_logic
    ;signal   rts_pad  : in    std_logic
    ;signal   debug_tx : in    std_logic
    );

end package tb_PicoSoC_pad_mux_pkg;

package body tb_PicoSoC_pad_mux_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   cts_b    : out   std_logic
    ;signal   cts_pad  : in    std_logic
    ;signal   rts_pad  : in    std_logic
    ;signal   debug_tx : in    std_logic
    ) is
    constant C_BANNER  : string   := "Welcome Back, Commander";
    -- Two loop lines of the firmware (about 60 characters each)
    constant C_QUIET   : time     := 120 * 10 * cfg.uart.bit_time;
    -- Three bytes of the HWLA UART (115200 baud)
    constant C_HWLA    : time     := 3 * 10 * (1 sec / 115200);
    variable v_line    : string(1 to 128);
    variable v_len     : natural;
    variable v_diff    : natural;

    -- Switches sw, then the firmware writes them into LED0
    procedure set_switch(constant sw : in std_logic_vector(8-1 downto 0)) is
    begin
      set_slv   (sw, clk, switch);
      wait_value(led0, sw, cfg, "LED0 = switches 0x" & to_hstring(sw));
    end procedure;

    -- RTS* driven by the user UART ('0' or '1', not the pull-up)
    procedure check_rts_driven(constant msg : in string) is
    begin
      check_value(rts_pad = '0' or rts_pad = '1', ERROR, msg & " : RTS* driven by the user UART (" & std_logic'image(rts_pad) & ")", C_TB_SCOPE);
    end procedure;

    -- CTS* of the cable released : the SoC does not drive the pad
    procedure check_cts_input(constant msg : in string) is
    begin
      cts_b <= 'Z';
      wait for cfg.clk_period;
      check_value(cts_pad = 'H', ERROR, msg & " : CTS* pad not driven by the SoC (" & std_logic'image(cts_pad) & ")", C_TB_SCOPE);
      cts_b <= '0';
    end procedure;

  begin
    log(ID_SEQUENCER, "pad_mux : functions of the UART pads selected by the switch MSBs", C_TB_SCOPE);

    -- 00 : user UART
    uart_get_line(v_line, v_len, uart_tx, cfg);
    check_value(v_line(1 to v_len) = C_BANNER, ERROR, "00 : UART banner : " & v_line(1 to v_len), C_TB_SCOPE);
    check_rts_driven("00");
    check_cts_input ("00");
    uart_send (x"3F", "00 : byte to echo", uart_rx, cfg);
    uart_check(x"3F", "00 : echo of the user UART", uart_tx, cfg);

    -- 11 : user UART
    set_switch(x"C0");
    check_rts_driven("11");
    check_cts_input ("11");
    uart_send (x"C3", "11 : byte to echo", uart_rx, cfg);
    uart_check(x"C3", "11 : echo of the user UART", uart_tx, cfg);

    -- 01 : HWLA UART. The firmware prints its loop lines (switch(5)) : the
    -- pad stays idle, the firmware does not wait (CTS* = 0)
    set_switch(x"60");
    wait for C_QUIET;
    check_stable(uart_tx, C_QUIET, ERROR, "01 : the loop lines of the user UART are not on the TX pad", C_TB_SCOPE);
    check_value (uart_tx, '1', ERROR, "01 : TX pad = idle HWLA UART", C_TB_SCOPE);
    check_value (rts_pad = 'H', ERROR, "01 : RTS* pad not driven", C_TB_SCOPE);
    check_cts_input("01");
    set_switch(x"61");

    -- 10 : JTAG chain. Out of a scan, no pad is driven by the SoC (TDI and
    -- TMS are inputs, TDO is driven in Shift-IR / Shift-DR only) ; the
    -- firmware does not wait on CTS*
    set_switch(x"A0");
    wait for C_QUIET;
    check_value(uart_tx = 'H', ERROR, "10 : TDI pad (TX) not driven by the SoC", C_TB_SCOPE);
    check_value(rts_pad = 'H', ERROR, "10 : TMS pad (RTS*) not driven by the SoC", C_TB_SCOPE);
    check_cts_input("10");
    set_switch(x"A1");

    -- Back to 00 : the end of the current loop line, then no line
    -- (switch(5) clear) ; the next loop line is on the TX pad
    set_switch(x"00");
    wait for C_QUIET;
    set_slv   (x"20", clk, switch);  -- the firmware writes LED0 after the line
    uart_get_line(v_line, v_len, uart_tx, cfg);
    check_value(v_len >= 5 and v_line(1 to 5) = "Loop ", ERROR, "00 : the loop lines are on the TX pad again : " & v_line(1 to v_len), C_TB_SCOPE);
    check_rts_driven("00");

    if cfg.debug and cfg.fault
    then
      -- 01 again : an error in CPU0 triggers the HWLA, its capture is sent
      -- on debug_uart_tx_o and on the TX pad (last : after the error, the
      -- firmware of CPU0 may no longer run without a supervisor)
      set_switch(x"40");
      check_value(debug_tx, '1', ERROR, "01 : no capture before the error", C_TB_SCOPE);
      inject_error(0, cfg, clk, inject);
      if debug_tx /= '0'
      then
        wait until debug_tx = '0' for cfg.timeout;
      end if;
      check_value(debug_tx, '0', ERROR, "01 : start bit of the capture on debug_uart_tx_o", C_TB_SCOPE);
      v_diff := 0;
      for i in 1 to C_HWLA / cfg.clk_period loop
        wait until rising_edge(clk);
        if uart_tx /= debug_tx
        then
          v_diff := v_diff + 1;
        end if;
      end loop;
      check_value(v_diff, 0, ERROR, "01 : TX pad = debug_uart_tx_o during 3 bytes of the capture", C_TB_SCOPE);
    end if;
  end procedure;

end package body tb_PicoSoC_pad_mux_pkg;
