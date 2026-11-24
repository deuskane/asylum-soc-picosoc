-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_uart_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_uart_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario uart of tb_PicoSoC, from reset (firmware user_uart*) :
--              lines printed by esw/demo/user.c on uart_tx_o
--              * "Welcome Back, Commander" after the reset
--              * then one line per loop iteration :
--                "Loop CCCCCCCC-SS-PP Lock 00 FF MB0 00 01 02 03 04 05 06 07 "
--                CCCCCCCC : loop counter, SS : switches,
--                PP : SPI byte (00 without SPI, CC(7:0) with the SPI loopback,
--                     byte CCCCCCCC of memory.mem with the SPI memory),
--                Lock : spinlock taken (00) then busy (FF),
--                MB0  : 8 bytes through the mailbox fifo0; the firmware also
--                       checks the mailbox sources of the user GIC (it stops
--                       printing on a mismatch)
--              A byte sent to the UART is echoed by the interruption routine
--              (UART source of the user GIC) : CTS* held from the end of
--              the banner while it is sent, the echo is then in the first
--              loop line. New switches : the
--              next line (switches read before) shows 00, the following
--              ones the new switches. During the loop lines : one it_user_i
--              pulse (LED1 = 1), the lines stay exact
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC)
-- 2026-11-22  1.1      mrosiere Switches 0x25 (MSBs 00 : the UART pads stay
--                               with the user UART)
-- 2026-11-23  1.2      mrosiere Loop line at every iteration (esw/demo/user.c) :
--                               echo with CTS* held (uart_echo), in the
--                               first loop line
-- 2026-11-23  1.3      mrosiere Switches 0xA5 again (the UART pads are
--                               selected by debug_mux_sel_i)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_uart_pkg is

  -- Banner then C_NB_LOOP "Loop" lines
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   it_user  : out   std_logic
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   cts_b    : out   std_logic
    );

end package tb_PicoSoC_uart_pkg;

package body tb_PicoSoC_uart_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   it_user  : out   std_logic
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   cts_b    : out   std_logic
    ) is
    constant C_BANNER  : string   := "Welcome Back, Commander";
    constant C_NB_LOOP : positive := 6;
    -- The UART pads stay with the user UART (debug_mux_sel_i 00) whatever
    -- the switches
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"A5";
    constant C_ECHO    : std_logic_vector(8-1 downto 0) := x"3F";  -- '?' : not in a loop line
    variable v_line    : string(1 to 128);
    variable v_len     : natural;
    variable v_spi     : natural;
    variable v_sw      : std_logic_vector(8-1 downto 0);
  begin
    log(ID_SEQUENCER, "uart : banner and loop lines of the firmware", C_TB_SCOPE);

    uart_get_line_quiet(v_line, v_len, uart_tx, cts_b, cfg);
    check_value(v_line(1 to v_len) = C_BANNER, ERROR, "UART banner : " & v_line(1 to v_len), C_TB_SCOPE);

    -- One line per loop iteration, the counter starts at 0. Line 0 : the
    -- echo of the interruption routine in it. Line 1 : switches read before
    -- the new ones
    for cpt in 0 to C_NB_LOOP-1 loop
      case cfg.spi_byte is
        when SPI_LOOPBACK => v_spi := cpt mod 256;
        when SPI_MEMORY   => v_spi := cpt+1 when cpt < 15 else 16#FF#; -- sim/mem/memory.mem
        when others       => v_spi := 0;
      end case;
      v_sw := x"00" when cpt < 2 else C_SW;

      -- Interruption in the middle of the loop lines
      if cpt = 2
      then
        pulse(4*cfg.clk_ratio, cfg.it_on, clk, it_user);
      end if;

      if cpt = 0
      then
        uart_echo(C_ECHO, "Echo of the interruption routine (UART source of the GIC)", v_line, v_len, uart_rx, uart_tx, cts_b, cfg);
        set_slv  (C_SW, clk, switch);
      else
        uart_get_line(v_line, v_len, uart_tx, cfg);
      end if;
      check_value(v_line(1 to v_len) = "Loop " & hex(cpt, 8) & "-" & to_hstring(v_sw) & "-" & hex(v_spi, 2) &
                                       " Lock 00 FF MB0 00 01 02 03 04 05 06 07 ",
                  ERROR, "UART loop line " & integer'image(cpt) & " : " & v_line(1 to v_len), C_TB_SCOPE);
    end loop;

    wait_value (led0, C_SW, cfg, "LED0 = switches");
    check_value(led1, x"01", ERROR, "LED1 : one interruption during the loop lines", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_uart_pkg;
