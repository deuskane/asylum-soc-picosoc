-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_pad_mux_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_pad_mux_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario pad_mux of tb_PicoSoC, from reset (firmware
--              user_uart*) : debug_mux_sel_i gives the 4 UART pads to one
--              function (the switches, MSBs 00, only follow on LED0)
--              * 00 : user UART (banner, echo of a byte in the first loop
--                line, CTS* held from the end of the banner while it is
--                sent), RTS* driven, CTS* not
--                driven by the SoC
--              * 11 : JTAG over the UART : TX pad driven by the UART of
--                jtag_bitbang (idle), CTS* and RTS* not driven
--              * 01 : HWLA UART : the loop lines of the firmware do not reach the TX pad, which stays idle ; the firmware
--                does not wait on CTS* (LED0 follows the switches) ; CTS*
--                and RTS* not driven
--              * 10 : JTAG : no pad driven out of a scan (TDI, TMS : inputs,
--                TDO : not driven, TDI and TMS of the cable released), the
--                firmware does not wait on CTS*
--              * back to 00 : the loop lines are on the TX pad again (a
--                quiet line with CTS*, the end of the current line, then a
--                full loop line)
--              * 01, with DEBUG_ENABLE, fault injection and HWLA_LINK
--                "uart" : an error in CPU0 triggers the HWLA, its capture is
--                on the TX pad, bit by bit equal to debug_uart_tx_o
--              Pull-ups of the tb : a pad driven by nobody is 'H' ; cts_b is
--              the CTS* of the cable ('Z' : released)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-22  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere Switches 11 : JTAG over the UART (was the
--                               user UART)
-- 2026-11-23  1.2      mrosiere Loop line at every iteration (esw/demo/user.c) :
--                               echo with CTS* held (uart_echo), back to 00
--                               after a quiet line (uart_quiet)
-- 2026-11-23  1.3      mrosiere Functions selected by debug_mux_sel_i (was the
--                               switch MSBs), switches with MSBs 00
-- 2026-11-27  1.4      mrosiere HWLA capture in mode 01 with HWLA_LINK "uart"
--                               only
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_pad_mux_pkg is

  -- Each code of debug_mux_sel_i
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   cts_b    : out   std_logic
    ;signal   cts_pad  : in    std_logic
    ;signal   rts_pad  : in    std_logic
    ;signal   jtag_if  : inout t_jtag_if
    ;signal   debug_tx : in    std_logic
    );

end package tb_PicoSoC_pad_mux_pkg;

package body tb_PicoSoC_pad_mux_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   cts_b    : out   std_logic
    ;signal   cts_pad  : in    std_logic
    ;signal   rts_pad  : in    std_logic
    ;signal   jtag_if  : inout t_jtag_if
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

    -- Function sel of the UART pads and switches sw, then the firmware
    -- writes the switches into LED0 (debug_mux_sel_i synchronized long before)
    procedure set_mux(constant sel : in std_logic_vector(2-1 downto 0)
                     ;constant sw  : in std_logic_vector(8-1 downto 0)) is
    begin
      set_slv   (sel, clk, mux_sel);
      set_slv   (sw , clk, switch);
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
    log(ID_SEQUENCER, "pad_mux : functions of the UART pads selected by debug_mux_sel_i", C_TB_SCOPE);

    -- 00 : user UART
    uart_get_line_quiet(v_line, v_len, uart_tx, cts_b, cfg);
    check_value(v_line(1 to v_len) = C_BANNER, ERROR, "00 : UART banner : " & v_line(1 to v_len), C_TB_SCOPE);
    uart_echo(x"3F", "00 : echo of the user UART", v_line, v_len, uart_rx, uart_tx, cts_b, cfg);
    check_rts_driven("00");
    check_cts_input ("00");

    -- 11 : JTAG over the UART : the UART of jtag_bitbang drives the TX pad
    -- (idle), CTS* and RTS* are not driven, the firmware does not wait
    set_mux(C_MUX_BITBANG, x"30");
    check_value(uart_tx = '1', ERROR, "11 : TX pad driven by the UART of jtag_bitbang (idle, " & std_logic'image(uart_tx) & ")", C_TB_SCOPE);
    check_value(rts_pad = 'H', ERROR, "11 : RTS* pad not driven", C_TB_SCOPE);
    check_cts_input("11");

    -- 01 : HWLA UART. The firmware prints its loop lines : the pad stays
    -- idle, the firmware does not wait (CTS* = 0)
    set_mux(C_MUX_HWLA   , x"20");
    wait for C_QUIET;
    check_stable(uart_tx, C_QUIET, ERROR, "01 : the loop lines of the user UART are not on the TX pad", C_TB_SCOPE);
    check_value (uart_tx, '1', ERROR, "01 : TX pad = idle HWLA UART", C_TB_SCOPE);
    check_value (rts_pad = 'H', ERROR, "01 : RTS* pad not driven", C_TB_SCOPE);
    check_cts_input("01");
    set_mux(C_MUX_HWLA   , x"21");

    -- 10 : JTAG chain. Out of a scan, no pad is driven by the SoC (TDI and
    -- TMS are inputs, TDO is driven in Shift-IR / Shift-DR only) ; the
    -- firmware does not wait on CTS*. TDI and TMS of the cable released
    set_mux(C_MUX_JTAG   , x"22");
    jtag_if.tdi <= 'Z';
    jtag_if.tms <= 'Z';
    wait for C_QUIET;
    check_value(uart_tx = 'H', ERROR, "10 : TDI pad (TX) not driven by the SoC", C_TB_SCOPE);
    check_value(rts_pad = 'H', ERROR, "10 : TMS pad (RTS*) not driven by the SoC", C_TB_SCOPE);
    check_value(cts_pad = 'H', ERROR, "10 : TDO pad (CTS*) not driven out of a scan", C_TB_SCOPE);
    jtag_if     <= init_jtag_if_signals;
    set_mux(C_MUX_JTAG   , x"23");

    -- Back to 00 : a quiet line (the TX pad changed in the middle of a
    -- byte), the end of the current loop line, then the next loop line
    set_mux(C_MUX_UART   , x"00");
    uart_quiet(cts_b, cfg);
    uart_get_line(v_line, v_len, uart_tx, cfg);
    uart_get_line(v_line, v_len, uart_tx, cfg);
    check_value(v_len >= 5 and v_line(1 to 5) = "Loop ", ERROR, "00 : the loop lines are on the TX pad again : " & v_line(1 to v_len), C_TB_SCOPE);
    check_rts_driven("00");

    if cfg.debug and cfg.fault and not cfg.hwla_jtag
    then
      -- 01 again : an error in CPU0 triggers the HWLA, its capture is sent
      -- on debug_uart_tx_o and on the TX pad (last : after the error, the
      -- firmware of CPU0 may no longer run without a supervisor)
      set_mux(C_MUX_HWLA   , x"10");
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
