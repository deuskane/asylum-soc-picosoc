-------------------------------------------------------------------------------
-- Title      : PicoSoC_jtag_over_uart
-- Project    :
-------------------------------------------------------------------------------
-- File       : PicoSoC_jtag_over_uart.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-11-23
-- Platform   :
-- Standard   : VHDL'2008
-------------------------------------------------------------------------------
-- Description: JTAG over the UART pads of PicoSoC_top (debug_mux_sel_i 11) :
--              jtag_bitbang of asylum-debug-jtag behind a UART (8 data bits,
--              no parity, 1 stop bit, JTAG_BAUD_RATE). OpenOCD
--              (remote_bitbang adapter, socat to the serial port) sends one
--              byte per change of TCK / TMS / TDI and one per TDO read
--              ('R'), jtag_bitbang answers '0' / '1' on uart_tx_o.
--              * jtag_ini_o drives the JTAG chain in place of the JTAG pads
--                (PicoSoC_pads), jtag_tgt_i is the TDO of the chain
--              * SRST ('s', 'u') is not connected (reset a CPU with ndmreset
--                of its debug unit) ; TRST* ('t', 'u') reaches the TAPs,
--                which ignore it (no TRST*) ; the LED of OpenOCD (blink) is
--                not used (no free LED)
--              * one clock (clk_i) and one reset : PicoSoC_top gives the
--                supervisor domain, so that a reset of the user SoC keeps
--                the link. TCK is a register of clk_i : a clock derived from
--                data for the TAPs (see the README for the constraints)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created (JTAG over the UART of PicoSoC_top)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.techmap_pkg.all;
use     asylum.uart_pkg.all;
use     asylum.jtag_pkg.all;

entity PicoSoC_jtag_over_uart is
  generic
    (FSYS_INT         : positive := 50_000_000 -- Frequency of clk_i (Hz)
    ;JTAG_BAUD_RATE   : integer  := 115200     -- Baud rate of the UART
    );
  port
    (clk_i            : in  std_logic
    ;arst_b_i         : in  std_logic

    -- UART (8N1, JTAG_BAUD_RATE) : commands of OpenOCD in, answers out
    ;uart_rx_i        : in  std_logic
    ;uart_tx_o        : out std_logic

    -- JTAG pins to the chain, TDO of the chain
    ;jtag_ini_o       : out jtag_ini_t
    ;jtag_tgt_i       : in  jtag_tgt_t
    );
end entity PicoSoC_jtag_over_uart;

architecture rtl of PicoSoC_jtag_over_uart is

  -- Baud tick every FSYS_INT/JTAG_BAUD_RATE cycles of clk_i
  constant BAUD_TICK_MAX         : std_logic_vector(16-1 downto 0) := std_logic_vector(to_unsigned(FSYS_INT/JTAG_BAUD_RATE-1, 16));

  signal   rx_b                : std_logic;
  signal   rx_b_sync           : std_logic;
  signal   rx_sync             : std_logic;
  signal   rx_tick             : std_logic;
  signal   rx_tick_half        : std_logic;
  signal   rx_tick_en          : std_logic;
  signal   tx_tick             : std_logic;
  signal   cmd_tdata           : std_logic_vector(8-1 downto 0);
  signal   cmd_tvalid          : std_logic;
  signal   cmd_tready          : std_logic;
  signal   answer_tdata        : std_logic_vector(8-1 downto 0);
  signal   answer_tvalid       : std_logic;
  signal   answer_tready       : std_logic;

begin  -- architecture rtl

  -- RX synchronized on clk_i (uart_rx_axis expects a synchronous input).
  -- sync2dffrn is reset to '0' : the inverted line is synchronized, so
  -- that RX is idle ('1') during the reset
  rx_b    <= not uart_rx_i;

  ins_bitbang_rx_sync : sync2dffrn
    port map
    (clk_i                   => clk_i
    ,arst_b_i                => arst_b_i
    ,d_i                     => rx_b
    ,q_o                     => rx_b_sync
    );

  rx_sync <= not rx_b_sync;

  ins_bitbang_rx_baud : uart_baud_rate_gen
    generic map
    (BAUD_TICK_CNT_WIDTH     => 16
    )
    port map
    (clk_i                   => clk_i
    ,arst_b_i                => arst_b_i
    ,baud_tick_en_i          => rx_tick_en
    ,baud_tick_o             => rx_tick
    ,baud_tick_half_o        => rx_tick_half
    ,cfg_baud_tick_cnt_max_i => BAUD_TICK_MAX
    );

  ins_bitbang_rx : uart_rx_axis
    generic map
    (WIDTH                   => 8
    )
    port map
    (clk_i                   => clk_i
    ,arst_b_i                => arst_b_i
    ,uart_rx_i               => rx_sync
    ,m_axis_tdata_o          => cmd_tdata
    ,m_axis_parity_error_o   => open
    ,m_axis_tvalid_o         => cmd_tvalid
    ,m_axis_tready_i         => cmd_tready
    ,baud_tick_i             => rx_tick
    ,baud_tick_half_i        => rx_tick_half
    ,baud_tick_en_o          => rx_tick_en
    ,parity_enable_i         => '0'
    ,parity_odd_i            => '0'
    ,last_parity_error_o     => open
    ,err_overrun_o           => open
    ,err_parity_o            => open
    ,err_framing_o           => open
    ,err_break_o             => open
    ,debug_o                 => open
    );

  ins_bitbang : jtag_bitbang
    port map
    (clk_i                   => clk_i
    ,arst_b_i                => arst_b_i
    ,s_axis_tdata_i          => cmd_tdata
    ,s_axis_tvalid_i         => cmd_tvalid
    ,s_axis_tready_o         => cmd_tready
    ,m_axis_tdata_o          => answer_tdata
    ,m_axis_tvalid_o         => answer_tvalid
    ,m_axis_tready_i         => answer_tready
    ,jtag_ini_o              => jtag_ini_o
    ,jtag_tgt_i              => jtag_tgt_i
    ,srst_o                  => open
    ,blink_o                 => open
    );

  ins_bitbang_tx_baud : uart_baud_rate_gen
    generic map
    (BAUD_TICK_CNT_WIDTH     => 16
    )
    port map
    (clk_i                   => clk_i
    ,arst_b_i                => arst_b_i
    ,baud_tick_en_i          => '1'
    ,baud_tick_o             => tx_tick
    ,baud_tick_half_o        => open
    ,cfg_baud_tick_cnt_max_i => BAUD_TICK_MAX
    );

  ins_bitbang_tx : uart_tx_axis
    generic map
    (WIDTH                   => 8
    )
    port map
    (clk_i                   => clk_i
    ,arst_b_i                => arst_b_i
    ,s_axis_tdata_i          => answer_tdata
    ,s_axis_tvalid_i         => answer_tvalid
    ,s_axis_tready_o         => answer_tready
    ,uart_tx_o               => uart_tx_o
    ,uart_cts_b_i            => '0'
    ,baud_tick_i             => tx_tick
    ,parity_enable_i         => '0'
    ,parity_odd_i            => '0'
    ,debug_o                 => open
    );

end architecture rtl;
