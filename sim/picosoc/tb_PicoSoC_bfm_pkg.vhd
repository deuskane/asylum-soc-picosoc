-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_bfm_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_bfm_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Helpers of the tb_PicoSoC scenarios : configuration record,
--              waits with a timeout, inputs driven on the falling edge of
--              clk_i, reset pulse, UART line receiver (UART VIP), quiet
--              UART line (CTS*) and echo during the loop lines, hexa
--              conversions of the UART lines printed by the firmware and
--              result line of the integration firmwares (esw/test/test_<ip>.c)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (helpers of tb_PicoSoC)
-- 2026-11-21  1.1      mrosiere wait_pass (integration firmwares)
-- 2026-11-22  1.2      mrosiere t_tb_cfg : debug, fault, supervisor, JTAG
--                               chain (t_jtag_chain)
-- 2026-11-23  1.3      mrosiere t_tb_cfg : bitbang (UART of JTAG over the
--                               UART pads)
-- 2026-11-23  1.4      mrosiere uart_get_line_quiet, uart_quiet, uart_echo
--                               (esw/demo/user.c prints a loop line at every
--                               iteration)
-- 2026-11-23  1.5      mrosiere C_MUX_* : codes of debug_mux_sel_i
-- 2026-11-24  1.6      mrosiere t_tb_cfg : hwla_depth, hwla_pre_trigger,
--                               hwla_ts_width (HWLA generics of the DUT)
-- 2026-11-26  1.7      mrosiere inject_error : one SoC clock cycle (the
--                               trap of PicoSoC_inject keeps the error), was
--                               100 cycles
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_uart;
use     bitvis_vip_uart.uart_bfm_pkg.all;

package tb_PicoSoC_bfm_pkg is

  constant C_TB_SCOPE  : string := "TB_PICOSOC";

  -- Byte read back from the SPI on each "Loop" line of the user firmware
  type t_spi_byte is (SPI_NONE      -- no SPI transfer printed : 00
                     ,SPI_LOOPBACK  -- SPI loopback : low byte of the loop counter
                     ,SPI_MEMORY    -- SPI memory : byte <counter> of memory.mem
                     );

  -- JTAG chain of PicoSoC_top : number of TAPs and position of each TAP
  -- from TDI (0 : first TAP after TDI), -1 : absent
  type t_jtag_chain is record
    nb_tap     : natural;
    user       : integer;            -- user CPU debugger of cluster 0 (USER_CPU_DEBUG_ENABLE), cluster i at user + i
    nb_user    : natural;            -- user CPU debuggers (one per cluster)
    supervisor : integer;            -- supervisor CPU debugger (SUPERVISOR_CPU_DEBUG_ENABLE)
    inject     : integer;            -- injection / status TAP (DEBUG_ENABLE)
  end record t_jtag_chain;

  -- Constants of the scenarios (computed from the generics in tb_PicoSoC)
  type t_tb_cfg is record
    clk_period : time;               -- period of clk_i
    clk_ratio  : positive;           -- clk_i cycles per cycle of the SoC clock
    timeout    : time;               -- maximum duration of one wait
    nb_cpu     : positive;           -- user CPUs (hello)
    tmr        : boolean;            -- USER_SAFETY = "tmr" (fault_diff)
    debug      : boolean;            -- DEBUG_ENABLE (HWLA)
    hwla_depth       : positive;     -- HWLA_DEPTH
    hwla_pre_trigger : natural;      -- HWLA_PRE_TRIGGER
    hwla_ts_width    : natural;      -- HWLA_TIMESTAMP_WIDTH
    fault      : boolean;            -- USER_FAULT_INJECTION with redundant CPUs : an injected error raises diff
    supervisor : boolean;            -- SUPERVISOR
    jtag       : t_jtag_chain;       -- JTAG chain
    spi_byte   : t_spi_byte;         -- "Loop" lines of the user firmware with UART
    it_on      : std_logic;          -- active level of it_user_i  (USER_IT_POLARITY)
    fault_on   : std_logic;          -- active level of inject_error_i (USER_FAULT_POLARITY)
    uart       : t_uart_bfm_config;  -- UART VIP configuration (bit time of the DUT)
    bitbang    : t_uart_bfm_config;  -- UART VIP configuration of JTAG over the UART (debug_mux_sel_i 11, JTAG_BAUD_RATE)
  end record t_tb_cfg;

  -- Function of the UART pads (debug_mux_sel_i of PicoSoC_top)
  constant C_MUX_UART    : std_logic_vector(2-1 downto 0) := "00";  -- user UART
  constant C_MUX_HWLA    : std_logic_vector(2-1 downto 0) := "01";  -- HWLA UART
  constant C_MUX_JTAG    : std_logic_vector(2-1 downto 0) := "10";  -- JTAG chain
  constant C_MUX_BITBANG : std_logic_vector(2-1 downto 0) := "11";  -- JTAG over the UART

  -- Never set : the UART receiver ends on a line feed or on its timeout
  signal   uart_no_terminate : std_logic := '0';

  -- Wait n rising edges of clk
  procedure wait_cycles
    (constant n        : in    natural
    ;signal   clk      : in    std_logic
    );

  -- Drive a vector after the falling edge of clk
  procedure set_slv
    (constant value    : in    std_logic_vector
    ;signal   clk      : in    std_logic
    ;signal   target   : out   std_logic_vector
    );

  -- Pulse of n cycles at the level active on a line, driven on the falling
  -- edges of clk
  procedure pulse
    (constant n        : in    positive
    ;constant active   : in    std_logic
    ;signal   clk      : in    std_logic
    ;signal   target   : out   std_logic
    );

  -- Error injected in a CPU : inject_error_i(cpu) active during one cycle of
  -- the SoC clock (cfg.clk_ratio cycles of clk) : the request sets the trap
  -- of the CPU (PicoSoC_inject), which flips an instruction bit of this CPU
  -- until the compare flags it. A longer request may outlive the reset of the
  -- user SoC that follows the detection and set the trap again

  procedure inject_error
    (constant cpu      : in    natural
    ;constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   inject   : out   std_logic_vector
    );

  -- Wait until target = exp (error after cfg.timeout)
  procedure wait_value
    (signal   target   : in    std_logic_vector
    ;constant exp      : in    std_logic_vector
    ;constant cfg      : in    t_tb_cfg
    ;constant msg      : in    string
    );

  -- Reset pulse of arst (active level : active), released on the falling edge
  -- of clk
  procedure do_reset
    (constant active   : in    std_logic
    ;signal   clk      : in    std_logic
    ;signal   arst     : out   std_logic
    );

  -- Receive one line of the UART (CR skipped, ends on LF)
  procedure uart_get_line
    (variable line     : out   string
    ;variable len      : out   natural
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    );

  -- Send a byte to the UART of the SoC
  procedure uart_send
    (constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;signal   uart_rx  : inout std_logic
    ;constant cfg      : in    t_tb_cfg
    );

  -- Expect a byte from the UART of the SoC (error after cfg.timeout)
  procedure uart_check
    (constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    );

  -- Receive one line, then hold CTS* inactive : raised on the CR, so that
  -- the LF is the last byte sent (the UART takes the next byte at the start
  -- of the stop bit of the previous one) ; released by uart_echo
  procedure uart_get_line_quiet
    (variable line     : out   string
    ;variable len      : out   natural
    ;signal   uart_tx  : in    std_logic
    ;signal   cts_b    : out   std_logic
    ;constant cfg      : in    t_tb_cfg
    );

  -- Quiet UART line at any time : CTS* held inactive during two characters
  -- (the byte in progress ends, the firmware waits on its next byte), then
  -- released. The next byte received starts on a start bit
  procedure uart_quiet
    (signal   cts_b    : out   std_logic
    ;constant cfg      : in    t_tb_cfg
    );

  -- Echo of a byte by the firmware while it prints its loop lines, after
  -- uart_get_line_quiet (CTS* held) : the byte is sent on a quiet line, CTS*
  -- released, then the next line is received ; the echo must be in it,
  -- line / len : the line without the echo
  procedure uart_echo
    (constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;variable line     : out   string
    ;variable len      : out   natural
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   cts_b    : out   std_logic
    ;constant cfg      : in    t_tb_cfg
    );

  -- Result line of an integration firmware (esw/include/test.h) : "PASS"
  -- expected ; "FAIL <step>" or no line (UART timeout) is an error
  procedure wait_pass
    (constant name     : in    string
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    );

  -- Active level of an input of polarity "high" / "low"
  function active_level
    (polarity : string
    ) return std_logic;

  -- Hexa string of value (width digits), as puthex of the firmware
  function hex
    (value : natural
    ;width : positive
    ) return string;

end package tb_PicoSoC_bfm_pkg;

package body tb_PicoSoC_bfm_pkg is

  procedure wait_cycles
    (constant n        : in    natural
    ;signal   clk      : in    std_logic
    ) is
  begin
    for i in 1 to n loop
      wait until rising_edge(clk);
    end loop;
  end procedure;

  procedure set_slv
    (constant value    : in    std_logic_vector
    ;signal   clk      : in    std_logic
    ;signal   target   : out   std_logic_vector
    ) is
  begin
    wait until falling_edge(clk);
    target <= value;
  end procedure;

  procedure pulse
    (constant n        : in    positive
    ;constant active   : in    std_logic
    ;signal   clk      : in    std_logic
    ;signal   target   : out   std_logic
    ) is
  begin
    wait until falling_edge(clk);
    target <= active;
    for i in 1 to n loop
      wait until falling_edge(clk);
    end loop;
    target <= not active;
  end procedure;

  procedure inject_error
    (constant cpu      : in    natural
    ;constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ) is
  begin
    log(ID_SEQUENCER_SUB, "Inject an error in CPU" & integer'image(cpu), C_TB_SCOPE);
    wait until falling_edge(clk);
    inject      <= (inject'range => not cfg.fault_on);
    inject(cpu) <= cfg.fault_on;
    for i in 1 to cfg.clk_ratio loop
      wait until falling_edge(clk);
    end loop;
    inject      <= (inject'range => not cfg.fault_on);
  end procedure;

  procedure wait_value
    (signal   target   : in    std_logic_vector
    ;constant exp      : in    std_logic_vector
    ;constant cfg      : in    t_tb_cfg
    ;constant msg      : in    string
    ) is
  begin
    await_value(target      => target,
                exp         => exp,
                min_time    => 0 ns,
                max_time    => cfg.timeout,
                alert_level => ERROR,
                msg         => msg,
                scope       => C_TB_SCOPE);
  end procedure;

  procedure do_reset
    (constant active   : in    std_logic
    ;signal   clk      : in    std_logic
    ;signal   arst     : out   std_logic
    ) is
  begin
    wait until falling_edge(clk);
    arst <= active;
    wait_cycles(10, clk);
    wait until falling_edge(clk);
    arst <= not active;
  end procedure;

  procedure uart_get_line
    (variable line     : out   string
    ;variable len      : out   natural
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    ) is
    variable v_byte    : std_logic_vector(8-1 downto 0);
    variable v_len     : natural := 0;
  begin
    line := (line'range => ' ');
    loop
      uart_receive(data_value     => v_byte,
                   msg            => "UART TX",
                   rx             => uart_tx,
                   terminate_loop => uart_no_terminate,
                   config         => cfg.uart,
                   scope          => C_TB_SCOPE);
      exit when v_byte = x"0A";
      if v_byte /= x"0D"
      then
        if v_len = line'length
        then
          alert(ERROR, "UART : line too long : " & line, C_TB_SCOPE);
          exit;
        end if;
        v_len                  := v_len+1;
        line(line'left+v_len-1) := character'val(to_integer(unsigned(v_byte)));
      end if;
    end loop;
    len := v_len;
  end procedure;

  procedure uart_send
    (constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;signal   uart_rx  : inout std_logic
    ;constant cfg      : in    t_tb_cfg
    ) is
  begin
    uart_transmit(data_value => data,
                  msg        => msg,
                  tx         => uart_rx,
                  config     => cfg.uart,
                  scope      => C_TB_SCOPE);
  end procedure;

  procedure uart_check
    (constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    ) is
  begin
    uart_expect(data_exp       => data,
                msg            => msg,
                rx             => uart_tx,
                terminate_loop => uart_no_terminate,
                max_receptions => 1,
                timeout        => cfg.timeout,
                alert_level    => ERROR,
                config         => cfg.uart,
                scope          => C_TB_SCOPE);
  end procedure;

  procedure uart_get_line_quiet
    (variable line     : out   string
    ;variable len      : out   natural
    ;signal   uart_tx  : in    std_logic
    ;signal   cts_b    : out   std_logic
    ;constant cfg      : in    t_tb_cfg
    ) is
    variable v_byte    : std_logic_vector(8-1 downto 0);
    variable v_len     : natural := 0;
  begin
    line := (line'range => ' ');
    loop
      uart_receive(data_value     => v_byte,
                   msg            => "UART TX",
                   rx             => uart_tx,
                   terminate_loop => uart_no_terminate,
                   config         => cfg.uart,
                   scope          => C_TB_SCOPE);
      exit when v_byte = x"0A";
      if v_byte = x"0D"
      then
        cts_b <= '1';
      elsif v_len = line'length
      then
        alert(ERROR, "UART : line too long : " & line, C_TB_SCOPE);
        exit;
      else
        v_len                   := v_len+1;
        line(line'left+v_len-1) := character'val(to_integer(unsigned(v_byte)));
      end if;
    end loop;
    len := v_len;
  end procedure;

  procedure uart_quiet
    (signal   cts_b    : out   std_logic
    ;constant cfg      : in    t_tb_cfg
    ) is
  begin
    cts_b <= '1';
    wait for 2 * 10 * cfg.uart.bit_time;
    cts_b <= '0';
  end procedure;

  procedure uart_echo
    (constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;variable line     : out   string
    ;variable len      : out   natural
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;signal   cts_b    : out   std_logic
    ;constant cfg      : in    t_tb_cfg
    ) is
    constant C_ECHO    : character := character'val(to_integer(unsigned(data)));
    variable v_line    : string(1 to line'length);
    variable v_len     : natural;
    variable v_pos     : natural := 0;
  begin
    uart_send(data, msg, uart_rx, cfg);
    cts_b <= '0';
    uart_get_line(v_line, v_len, uart_tx, cfg);
    for i in v_len downto 1 loop
      if v_line(i) = C_ECHO
      then
        v_pos := i;
      end if;
    end loop;
    check_value(v_pos /= 0, ERROR, msg & " : echo in the line " & v_line(1 to v_len), C_TB_SCOPE);
    if v_pos /= 0
    then
      v_line(v_pos to v_len-1) := v_line(v_pos+1 to v_len);
      v_len                    := v_len-1;
    end if;
    line := v_line;
    len  := v_len;
  end procedure;

  procedure wait_pass
    (constant name     : in    string
    ;signal   uart_tx  : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    ) is
    variable v_line    : string(1 to 32);
    variable v_len     : natural;
  begin
    uart_get_line(v_line, v_len, uart_tx, cfg);
    check_value(v_line(1 to v_len) = "PASS", ERROR, name & " : result of the firmware : " & v_line(1 to v_len), C_TB_SCOPE);
  end procedure;

  function active_level
    (polarity : string
    ) return std_logic is
  begin
    if polarity = "high"
    then
      return '1';
    else
      return '0';
    end if;
  end function;

  function hex
    (value : natural
    ;width : positive
    ) return string is
  begin
    return to_hstring(std_logic_vector(to_unsigned(value, 4*width)));
  end function;

end package body tb_PicoSoC_bfm_pkg;
