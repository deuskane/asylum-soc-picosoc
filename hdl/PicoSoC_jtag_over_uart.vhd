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
--              jtag_bitbang of asylum-debug-jtag behind uart_core of
--              asylum-communication-uart (8 data bits, no parity, 1 stop
--              bit, JTAG_BAUD_RATE, uart_rx_i synchronized inside). OpenOCD
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
-- 2026-11-23  1.1      mrosiere uart_core in place of the RX synchronizer,
--                               uart_rx_axis, uart_tx_axis and their
--                               uart_baud_rate_gen
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
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

  signal   cmd_tdata           : std_logic_vector(8-1 downto 0);
  signal   cmd_tvalid          : std_logic;
  signal   cmd_tready          : std_logic;
  signal   answer_tdata        : std_logic_vector(8-1 downto 0);
  signal   answer_tvalid       : std_logic;
  signal   answer_tready       : std_logic;

begin  -- architecture rtl

  -- Receiver (commands) and transmitter (answers) : no parity, CTS
  -- ignored ; uart_rx_i is synchronized inside uart_core
  ins_uart_core : uart_core
    generic map
    (TX_ENABLE               => true
    ,RX_ENABLE               => true
    ,WIDTH                   => 8
    ,BAUD_TICK_CNT_WIDTH     => 16
    )
    port map
    (clk_i                   => clk_i
    ,arst_b_i                => arst_b_i
    ,cfg_baud_tick_cnt_max_i => BAUD_TICK_MAX
    ,cfg_tx_enable_i         => '1'
    ,cfg_tx_parity_enable_i  => '0'
    ,cfg_tx_parity_odd_i     => '0'
    ,cfg_rx_enable_i         => '1'
    ,cfg_rx_parity_enable_i  => '0'
    ,cfg_rx_parity_odd_i     => '0'
    ,s_axis_tdata_i          => answer_tdata
    ,s_axis_tvalid_i         => answer_tvalid
    ,s_axis_tready_o         => answer_tready
    ,uart_tx_o               => uart_tx_o
    ,uart_cts_b_i            => '0'
    ,uart_rx_i               => uart_rx_i
    ,m_axis_tdata_o          => cmd_tdata
    ,m_axis_parity_error_o   => open
    ,m_axis_tvalid_o         => cmd_tvalid
    ,m_axis_tready_i         => cmd_tready
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

end architecture rtl;
