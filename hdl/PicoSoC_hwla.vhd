-------------------------------------------------------------------------------
-- Title      : PicoSoC_hwla
-- Project    :
-------------------------------------------------------------------------------
-- File       : PicoSoC_hwla.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-11-23
-- Platform   :
-- Standard   : VHDL'2008
-------------------------------------------------------------------------------
-- Description: HWLA (logic analyzer) of PicoSoC_top and its UART
--              * hwla of asylum-debug-hwla : 64 samples, 32 before the
--                trigger, 16-bit timestamp, changes only ; probe_i is
--                unconstrained (the width of the probes comes from the
--                actual : map a signal, GHDL 6.0.0 crashes on an expression)
--              * captures sent byte per byte on uart_tx_o : uart_core
--                (transmitter only), HWLA_BAUD_RATE (115200 by default :
--                a bit every FSYS_INT/HWLA_BAUD_RATE cycles of clk_i),
--                8 bits, no parity, 1 stop bit
--              * one clock (clk_i) and one reset for the trigger and the
--                extraction domains
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created (HWLA of PicoSoC_top)
-- 2026-11-23  1.1      mrosiere HWLA_BAUD_RATE (was the constant 115200)
-- 2026-11-23  1.2      mrosiere uart_core (TX only) in place of uart_tx_axis
--                               and uart_baud_rate_gen
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.hwla_pkg.all;
use     asylum.uart_pkg.all;

entity PicoSoC_hwla is
  generic
    (FSYS_INT         : positive := 50_000_000 -- Frequency of clk_i (Hz)
    ;HWLA_BAUD_RATE   : integer  := 115200     -- Baud rate of the UART of the captures
    );
  port
    (clk_i            : in  std_logic
    ;arst_b_i         : in  std_logic

    -- Probes (any width) and trigger
    ;probe_i          : in  std_logic_vector
    ;trigger_i        : in  std_logic

    -- Captures : UART 8N1, HWLA_BAUD_RATE
    ;uart_tx_o        : out std_logic
    );
end entity PicoSoC_hwla;

architecture rtl of PicoSoC_hwla is

  -- Baud tick every FSYS_INT/HWLA_BAUD_RATE cycles of clk_i
  constant HWLA_BAUD_TICK_MAX  : std_logic_vector(16-1 downto 0) := std_logic_vector(to_unsigned(FSYS_INT/HWLA_BAUD_RATE-1, 16));

  signal   hwla_tdata          : std_logic_vector(8-1 downto 0);
  signal   hwla_tvalid         : std_logic;
  signal   hwla_tready         : std_logic;

begin  -- architecture rtl

  ins_hwla : hwla
    generic map
    (DEPTH                => 64    -- Small RAM (64 x probes + timestamp) : a few tens of instructions
    ,PRE_TRIGGER          => 32    -- Half of the capture before the trigger
    ,TIMESTAMP_WIDTH      => 16    -- A sample at least every 65536 cycles
    ,CHANGE_ONLY          => true  -- A CPU waiting on the bus fills no sample
    ,TDATA_WIDTH          => 8     -- One byte per beat, for the UART
    )
    port map
    (trig_clk_i           => clk_i
    ,trig_arst_b_i        => arst_b_i
    ,arm_i                => '1'   -- A new capture after each extraction
    ,trigger_i            => trigger_i
    ,probe_i              => probe_i
    ,armed_o              => open
    ,triggered_o          => open
    ,extract_clk_i        => clk_i
    ,extract_arst_b_i     => arst_b_i
    ,m_axis_tdata_o       => hwla_tdata
    ,m_axis_tvalid_o      => hwla_tvalid
    ,m_axis_tready_i      => hwla_tready
    ,m_axis_tlast_o       => open
    );

  -- Transmitter only (RX_ENABLE false) : no parity, CTS ignored
  ins_uart_core : uart_core
    generic map
    (TX_ENABLE               => true
    ,RX_ENABLE               => false
    ,WIDTH                   => 8
    ,BAUD_TICK_CNT_WIDTH     => 16
    )
    port map
    (clk_i                   => clk_i
    ,arst_b_i                => arst_b_i
    ,cfg_baud_tick_cnt_max_i => HWLA_BAUD_TICK_MAX
    ,cfg_tx_enable_i         => '1'
    ,cfg_tx_parity_enable_i  => '0'
    ,cfg_tx_parity_odd_i     => '0'
    ,cfg_rx_enable_i         => '0'
    ,cfg_rx_parity_enable_i  => '0'
    ,cfg_rx_parity_odd_i     => '0'
    ,s_axis_tdata_i          => hwla_tdata
    ,s_axis_tvalid_i         => hwla_tvalid
    ,s_axis_tready_o         => hwla_tready
    ,uart_tx_o               => uart_tx_o
    ,uart_cts_b_i            => '0'
    ,uart_rx_i               => '1'
    ,m_axis_tdata_o          => open
    ,m_axis_parity_error_o   => open
    ,m_axis_tvalid_o         => open
    ,m_axis_tready_i         => '1'
    ,err_overrun_o           => open
    ,err_parity_o            => open
    ,err_framing_o           => open
    ,err_break_o             => open
    ,debug_o                 => open
    );

end architecture rtl;
