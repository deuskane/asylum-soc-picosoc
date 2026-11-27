-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_sequence_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_sequence_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Firmware esw/demo/user_loop.c (LED0 = switches and one UART
--              line per iteration, "Loop <loop> <xorwow>", 8 hexadecimal
--              digits each) :
--              * the reference : the line of each loop number, xorwow of
--                Marsaglia computed here from the seed of the firmware
--              * a UART line receiver with a timeout (no alert : a firmware
--                that stops is a result of the fault scenarios)
--              * the line checks (a run of reference lines ; the restart
--                from the loop 0 after a reset of the user SoC)
--              * scenario sequence, from reset : the first 2 x C_NB_LINES
--                lines are the reference ; LED0 follows the switches (0x5A,
--                then 0xA5, set before a run of lines, checked after it :
--                the loop that prints a line reads the switches first) ;
--                led_diff_o stays 0
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-27  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_sequence_pkg is

  -- A line of the firmware : "Loop xxxxxxxx xxxxxxxx" (CR LF removed)
  subtype  t_loop_line   is string(1 to 22);
  constant C_NB_LINES    : positive := 3;

  -- Line of the loop number n
  function loop_line
    (n        : natural
    ) return t_loop_line;

  -- Receive one line (CR skipped, ends on LF) : ok false when no start bit
  -- comes within cfg.timeout (the firmware stopped)
  procedure get_line
    (variable line     : out   string
    ;variable len      : out   natural
    ;variable ok       : out   boolean
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    );

  -- The next lines are the reference lines first .. first+n-1
  procedure check_lines
    (constant first    : in    natural
    ;constant n        : in    positive
    ;constant msg      : in    string
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    );

  -- After a reset of the user SoC : wait (at most max lines) for the line
  -- of the loop 0 (the end of a received line : a line cut by the reset may
  -- precede it), then the next lines are the reference lines 1 .. n
  procedure check_restart
    (constant n        : in    positive
    ;constant msg      : in    string
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    );

  -- Scenario sequence
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_sequence_pkg;

package body tb_PicoSoC_sequence_pkg is

  function hex32
    (value    : unsigned(32-1 downto 0)
    ) return string is
  begin
    return to_hstring(std_logic_vector(value));
  end function;

  function loop_line
    (n        : natural
    ) return t_loop_line is
    -- Seed of the firmware (Marsaglia)
    variable x, y, z, w, v, d, t, r : unsigned(32-1 downto 0);
  begin
    x := to_unsigned(123456789, 32);
    y := to_unsigned(362436069, 32);
    z := to_unsigned(521288629, 32);
    w := to_unsigned( 88675123, 32);
    v := to_unsigned(  5783321, 32);
    d := to_unsigned(  6615241, 32);
    for i in 0 to n loop
      t := x xor shift_right(x, 2);
      x := y;
      y := z;
      z := w;
      w := v;
      v := (v xor shift_left(v, 4)) xor (t xor shift_left(t, 1));
      d := d + 362437;
      r := d + v;
    end loop;
    return "Loop " & hex32(to_unsigned(n, 32)) & " " & hex32(r);
  end function;

  procedure get_line
    (variable line     : out   string
    ;variable len      : out   natural
    ;variable ok       : out   boolean
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    ) is
    constant C_BIT     : time := cfg.uart.bit_time;
    variable v_byte    : std_logic_vector(8-1 downto 0);
    variable v_len     : natural := 0;
  begin
    line := (line'range => ' ');
    ok   := true;
    loop
      -- Start bit (from the idle level), then the 8 data bits in their
      -- middle, LSB first ; the stop bit is not checked
      if to_x01(uart_tx) /= '1'
      then
        wait until to_x01(uart_tx) = '1' for cfg.timeout;
      end if;
      wait until to_x01(uart_tx) = '0' for cfg.timeout;
      if to_x01(uart_tx) /= '0'
      then
        ok := false;
        exit;
      end if;
      wait for C_BIT + C_BIT/2;
      for b in 0 to 7 loop
        v_byte(b) := to_x01(uart_tx);
        wait for C_BIT;
      end loop;
      exit when v_byte = x"0A";
      if v_byte /= x"0D" and v_len < line'length
      then
        v_len                   := v_len+1;
        line(line'left+v_len-1) := character'val(to_integer(unsigned(v_byte)));
      end if;
    end loop;
    len := v_len;
  end procedure;

  procedure check_lines
    (constant first    : in    natural
    ;constant n        : in    positive
    ;constant msg      : in    string
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    ) is
    variable v_line    : string(1 to 64);
    variable v_len     : natural;
    variable v_ok      : boolean;
  begin
    for i in first to first+n-1 loop
      get_line(v_line, v_len, v_ok, uart_tx, cfg);
      check_value(v_ok and v_line(1 to v_len) = loop_line(i), ERROR,
                  msg & " : line " & v_line(1 to v_len) & " = " & loop_line(i), C_TB_SCOPE);
    end loop;
  end procedure;

  procedure check_restart
    (constant n        : in    positive
    ;constant msg      : in    string
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    ) is
    constant C_LINE0   : t_loop_line := loop_line(0);
    variable v_line    : string(1 to 64);
    variable v_len     : natural;
    variable v_ok      : boolean;
    variable v_found   : boolean := false;
  begin
    for i in 1 to 4 loop
      get_line(v_line, v_len, v_ok, uart_tx, cfg);
      v_found := v_ok and v_len >= C_LINE0'length and v_line(v_len-C_LINE0'length+1 to v_len) = C_LINE0;
      exit when v_found or not v_ok;
    end loop;
    check_value(v_found, ERROR, msg & " : the firmware restarts (" & C_LINE0 & ")", C_TB_SCOPE);
    check_lines(1, n, msg & ", after the restart", uart_tx, cfg);
  end procedure;

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    ) is
    constant C_SW1     : std_logic_vector(8-1 downto 0) := x"5A";
    constant C_SW2     : std_logic_vector(8-1 downto 0) := x"A5";
    variable v_t0      : time;
  begin
    log(ID_SEQUENCER, "sequence : the first lines of user_loop.c are the xorwow sequence, LED0 = switches", C_TB_SCOPE);
    v_t0 := now;
    set_slv     (C_SW1, clk, switch);
    check_lines (0, C_NB_LINES, "from reset", uart_tx, cfg);
    check_value (led0, C_SW1, ERROR, "LED0 = switches 0x" & to_hstring(C_SW1), C_TB_SCOPE);
    set_slv     (C_SW2, clk, switch);
    check_lines (C_NB_LINES, C_NB_LINES, "new switches", uart_tx, cfg);
    check_value (led0, C_SW2, ERROR, "LED0 = switches 0x" & to_hstring(C_SW2), C_TB_SCOPE);
    check_stable(led_diff, now - v_t0, ERROR, "led_diff stable", C_TB_SCOPE);
    check_value (led_diff, "000", ERROR, "led_diff = 0 : no error", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_sequence_pkg;
