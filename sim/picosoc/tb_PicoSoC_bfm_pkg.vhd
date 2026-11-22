-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_bfm_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_bfm_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Helpers of the tb_PicoSoC scenarios : configuration record,
--              waits with a timeout, inputs driven on the falling edge of
--              clk_i, reset pulse, UART line receiver (UART VIP), hexa
--              conversions of the UART lines printed by the firmware and
--              result line of the integration firmwares (esw/test_<ip>.c)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (helpers of tb_PicoSoC)
-- 2026-11-21  1.1      mrosiere wait_pass (integration firmwares)
-- 2026-11-22  1.2      mrosiere t_tb_cfg : debug, fault, supervisor, JTAG
--                               chain (t_jtag_chain)
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
    user       : integer;            -- user CPU debugger (USER_CPU_DEBUG_ENABLE)
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
    fault      : boolean;            -- USER_FAULT_INJECTION with redundant CPUs : an injected error raises diff
    supervisor : boolean;            -- SUPERVISOR
    jtag       : t_jtag_chain;       -- JTAG chain
    spi_byte   : t_spi_byte;         -- "Loop" lines of the user firmware with UART
    it_on      : std_logic;          -- active level of it_user_i  (USER_IT_POLARITY)
    fault_on   : std_logic;          -- active level of inject_error_i (USER_FAULT_POLARITY)
    uart       : t_uart_bfm_config;  -- UART VIP configuration (bit time of the DUT)
  end record t_tb_cfg;

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

  -- Error injected in a CPU : inject_error_i(cpu) active during C_INJECT_CYCLES
  -- cycles (an instruction bit of this CPU flipped)
  constant C_INJECT_CYCLES : positive := 100;

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
    for i in 1 to C_INJECT_CYCLES loop
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
