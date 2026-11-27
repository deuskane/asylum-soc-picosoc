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
--              * hwla of asylum-debug-hwla : HWLA_DEPTH samples (64 by
--                default), HWLA_PRE_TRIGGER before the trigger (32),
--                HWLA_TIMESTAMP_WIDTH-bit timestamp (16), changes only ;
--                probe_i is
--                unconstrained (the width of the probes comes from the
--                actual : map a signal, GHDL 6.0.0 crashes on an expression)
--              * captures sent byte per byte on the link HWLA_LINK :
--                - "uart" : on uart_tx_o, uart_core (transmitter only),
--                  HWLA_BAUD_RATE (115200 by default : a bit every
--                  FSYS_INT/HWLA_BAUD_RATE cycles of clk_i), 8 bits, no
--                  parity, 1 stop bit ; jtag_tgt_o is a wire of the chain
--                - "jtag" : to the TX FIFO of jtag_axis (asylum-debug-jtag,
--                  8-bit words, TX only), read by the debugger through its
--                  TAP (IDCODE PICOSOC_JTAG_IDCODE_HWLA), a stage of the JTAG
--                  chain ; uart_tx_o stays idle (1). The HWLA waits while the
--                  FIFO is full (tready 0) : the capture stays in its RAM
--                  until the debugger reads it, a new capture starts after
--                  its last byte
--              * status_o : flags of the HWLA, from the LSB : arm (arm_i,
--                tied to 1), armed (capture started, trigger not yet seen),
--                triggered (trigger seen, capture not yet extracted),
--                sending (a byte of the capture offered to the link : the
--                extraction goes on, at the pace of the link)
--              * one clock (clk_i) and one reset for the trigger and the
--                extraction domains (and jtag_axis)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created (HWLA of PicoSoC_top)
-- 2026-11-23  1.1      mrosiere HWLA_BAUD_RATE (was the constant 115200)
-- 2026-11-23  1.2      mrosiere uart_core (TX only) in place of uart_tx_axis
--                               and uart_baud_rate_gen
-- 2026-11-24  1.3      mrosiere HWLA_DEPTH, HWLA_PRE_TRIGGER,
--                               HWLA_TIMESTAMP_WIDTH (were 64, 32, 16)
-- 2026-11-27  1.4      mrosiere HWLA_LINK : captures on the UART or on the
--                               TX FIFO of jtag_axis (its TAP in the chain)
-- 2026-11-27  1.5      mrosiere status_o : arm, armed, triggered, sending
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.hwla_pkg.all;
use     asylum.uart_pkg.all;
use     asylum.jtag_pkg.all;
use     asylum.PicoSoC_pkg.all;

entity PicoSoC_hwla is
  generic
    (FSYS_INT         : positive := 50_000_000 -- Frequency of clk_i (Hz)
    ;HWLA_BAUD_RATE   : integer  := 115200     -- Baud rate of the UART of the captures
    ;HWLA_DEPTH       : positive := 64         -- Samples of a capture (power of 2) : a few tens of instructions
    ;HWLA_PRE_TRIGGER : natural  := 32         -- Samples before the trigger sample (0 to HWLA_DEPTH-1)
    ;HWLA_TIMESTAMP_WIDTH : natural := 16      -- Timestamp of a sample (16 : a sample at least every 65536 cycles)
    ;HWLA_LINK        : string   := "uart"     -- Link of the captures : "uart" (uart_tx_o) / "jtag" (TAP of jtag_axis)
    );
  port
    (clk_i            : in  std_logic
    ;arst_b_i         : in  std_logic

    -- Probes (any width) and trigger
    ;probe_i          : in  std_logic_vector
    ;trigger_i        : in  std_logic

    -- Flags, from the LSB : arm, armed, triggered, sending
    ;status_o         : out std_logic_vector(4-1 downto 0)

    -- Captures, HWLA_LINK "uart" : UART 8N1, HWLA_BAUD_RATE ("jtag" : 1)
    ;uart_tx_o        : out std_logic

    -- Captures, HWLA_LINK "jtag" : TAP of jtag_axis, a stage of the JTAG
    -- chain (TCK resynchronized on clk_i) ; "uart" : a wire (TDO = TDI)
    ;jtag_ini_i       : in  jtag_ini_t
    ;jtag_tgt_o       : out jtag_tgt_t
    );
end entity PicoSoC_hwla;

architecture rtl of PicoSoC_hwla is

  -- Baud tick every FSYS_INT/HWLA_BAUD_RATE cycles of clk_i
  constant HWLA_BAUD_TICK_MAX  : std_logic_vector(16-1 downto 0) := std_logic_vector(to_unsigned(FSYS_INT/HWLA_BAUD_RATE-1, 16));

  signal   hwla_tdata          : std_logic_vector(8-1 downto 0);
  signal   hwla_tvalid         : std_logic;
  signal   hwla_tready         : std_logic;
  signal   hwla_arm            : std_logic;
  signal   hwla_armed          : std_logic;
  signal   hwla_triggered      : std_logic;

begin  -- architecture rtl

  hwla_arm <= '1';  -- A new capture after each extraction

  ins_hwla : hwla
    generic map
    (DEPTH                => HWLA_DEPTH
    ,PRE_TRIGGER          => HWLA_PRE_TRIGGER
    ,TIMESTAMP_WIDTH      => HWLA_TIMESTAMP_WIDTH
    ,CHANGE_ONLY          => true  -- A CPU waiting on the bus fills no sample
    ,TDATA_WIDTH          => 8     -- One byte per beat, for the UART or jtag_axis
    )
    port map
    (trig_clk_i           => clk_i
    ,trig_arst_b_i        => arst_b_i
    ,arm_i                => hwla_arm
    ,trigger_i            => trigger_i
    ,probe_i              => probe_i
    ,armed_o              => hwla_armed
    ,triggered_o          => hwla_triggered
    ,extract_clk_i        => clk_i
    ,extract_arst_b_i     => arst_b_i
    ,m_axis_tdata_o       => hwla_tdata
    ,m_axis_tvalid_o      => hwla_tvalid
    ,m_axis_tready_i      => hwla_tready
    ,m_axis_tlast_o       => open
    );

  status_o <= hwla_tvalid & hwla_triggered & hwla_armed & hwla_arm;

  -----------------------------------------------------------------------------
  -- HWLA_LINK "uart" : transmitter only (RX_ENABLE false), no parity, CTS
  -- ignored ; no TAP
  -----------------------------------------------------------------------------
  gen_uart: if HWLA_LINK = "uart"
  generate
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

    jtag_tgt_o <= (tdo => jtag_ini_i.tdi, tdo_en => '0');
  end generate gen_uart;

  -----------------------------------------------------------------------------
  -- HWLA_LINK "jtag" : TX FIFO of jtag_axis (8-bit words, TX only), read by
  -- the debugger with its instruction TX. No TRST* pin : trst_n tied to 1
  -- (its TAP is reset by arst_b_i and by 5 TCK with TMS = 1)
  -----------------------------------------------------------------------------
  gen_jtag: if HWLA_LINK = "jtag"
  generate
    signal   axis_jtag_ini       : jtag_ini_t;
  begin
    axis_jtag_ini <= (tck => jtag_ini_i.tck, trst_n => '1', tms => jtag_ini_i.tms, tdi => jtag_ini_i.tdi);

    ins_jtag_axis : jtag_axis
      generic map
      (DATA_WIDTH              => 8
      ,TX_ENABLE               => true
      ,RX_ENABLE               => false
      ,DEPTH_TX                => 4      -- The capture waits in the RAM of the HWLA
      ,IDCODE                  => PICOSOC_JTAG_IDCODE_HWLA
      )
      port map
      (clk_i                   => clk_i
      ,arst_b_i                => arst_b_i
      ,jtag_ini_i              => axis_jtag_ini
      ,jtag_tgt_o              => jtag_tgt_o
      ,s_axis_tdata_i          => hwla_tdata
      ,s_axis_tvalid_i         => hwla_tvalid
      ,s_axis_tready_o         => hwla_tready
      ,m_axis_tdata_o          => open
      ,m_axis_tvalid_o         => open
      ,m_axis_tready_i         => '1'
      );

    uart_tx_o <= '1';  -- UART idle level
  end generate gen_jtag;

end architecture rtl;
