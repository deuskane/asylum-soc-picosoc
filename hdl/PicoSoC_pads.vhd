-------------------------------------------------------------------------------
-- Title      : PicoSoC_pads
-- Project    :
-------------------------------------------------------------------------------
-- File       : PicoSoC_pads.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-11-23
-- Platform   :
-- Standard   : VHDL'2008
-------------------------------------------------------------------------------
-- Description: Pads of PicoSoC_top : the board side on one side, the signals
--              of the functions on the other
--              * UART pads (FTDI MPSSE pinout) shared by 4 functions
--                (jtag_pad_mux), selected by debug_mux_sel_i :
--                00 user UART ; 01 HWLA UART (TX only) ; 10 JTAG chain ;
--                11 JTAG over the UART (UART of jtag_bitbang)
--              * SPI pads (obuf, iobuf) : USER_SPI_NB_IO data lanes, the
--                other inputs of the SPI read 0
--              * I2C pads, open drain (iobuf)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created (pads of PicoSoC_top)
-- 2026-11-23  1.1      mrosiere Switches 11 : JTAG over the UART (RX / TX
--                               of jtag_bitbang, which drives the JTAG chain)
-- 2026-11-23  1.2      mrosiere debug_mux_sel_i (was switch_i, the two MSBs
--                               of the switches)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.techmap_pkg.all;
use     asylum.jtag_pkg.all;

entity PicoSoC_pads is
  generic
    (USER_SPI_NB_IO   : natural  := 8          -- SPI data lanes with a pad (up to 8)
    );
  port
    (clk_i            : in    std_logic
    ;arst_b_i         : in    std_logic

    -- Function of the UART pads (asynchronous)
    ;debug_mux_sel_i  : in    std_logic_vector(2-1 downto 0)

    -- Pads : UART / JTAG (FTDI MPSSE AD0 to AD3), SPI, I2C
    ;uart_rx_i        : in    std_logic -- RX   / TCK
    ;uart_tx_io       : inout std_logic -- TX   / TDI
    ;uart_cts_b_io    : inout std_logic -- CTS* / TDO
    ;uart_rts_b_io    : inout std_logic -- RTS* / TMS
    ;spi_sclk_io      : inout std_logic
    ;spi_cs_b_io      : inout std_logic
    ;spi_io_io        : inout std_logic_vector(USER_SPI_NB_IO-1 downto 0)
    ;i2c_scl_io       : inout std_logic
    ;i2c_sda_io       : inout std_logic

    -- User UART
    ;uart_tx_i        : in    std_logic
    ;uart_rx_o        : out   std_logic
    ;uart_cts_b_o     : out   std_logic
    ;uart_rts_b_i     : in    std_logic
    -- HWLA UART (TX only)
    ;debug_uart_tx_i  : in    std_logic
    -- JTAG chain : driven by the JTAG pads (debug_mux_sel_i 10) or by
    -- jtag_bitbang (debug_mux_sel_i 11)
    ;jtag_ini_o       : out   jtag_ini_t
    ;jtag_tgt_i       : in    jtag_tgt_t
    -- JTAG over the UART (jtag_bitbang and its UART)
    ;bitbang_tx_i     : in    std_logic
    ;bitbang_rx_o     : out   std_logic
    ;bitbang_jtag_i   : in    jtag_ini_t
    -- SPI (8 data lanes of the SPI)
    ;spi_sclk_i       : in    std_logic
    ;spi_sclk_oe_i    : in    std_logic
    ;spi_cs_b_i       : in    std_logic
    ;spi_cs_b_oe_i    : in    std_logic
    ;spi_io_i         : in    std_logic_vector(8-1 downto 0)
    ;spi_io_oe_i      : in    std_logic_vector(8-1 downto 0)
    ;spi_io_o         : out   std_logic_vector(8-1 downto 0)
    -- I2C (open drain : the output enable pulls the line low)
    ;i2c_scl_i        : in    std_logic
    ;i2c_scl_oe_i     : in    std_logic
    ;i2c_scl_o        : out   std_logic
    ;i2c_sda_i        : in    std_logic
    ;i2c_sda_oe_i     : in    std_logic
    ;i2c_sda_o        : out   std_logic
    );
end entity PicoSoC_pads;

architecture rtl of PicoSoC_pads is

  -- UART pads : 4 functions selected by debug_mux_sel_i (synchronized). The pads of each function are given by the constants
  -- PAD_* and by the block "Pad multiplexer" below (one place to change).
  -- Pads in the order of the FTDI MPSSE pins AD0 to AD3
  constant NB_FUNC                      : positive := 4;
  constant FUNC_UART                    : natural  := 0; -- 00 : user UART
  constant FUNC_HWLA                    : natural  := 1; -- 01 : HWLA UART (TX only)
  constant FUNC_JTAG                    : natural  := 2; -- 10 : JTAG chain
  constant FUNC_BITBANG                 : natural  := 3; -- 11 : JTAG over the UART (jtag_bitbang)
  constant PAD_RX                       : natural  := 0; -- uart_rx_i     : RX   (in)  / TCK (in)
  constant PAD_TX                       : natural  := 1; -- uart_tx_io    : TX   (out) / TDI (in)
  constant PAD_CTS_B                    : natural  := 2; -- uart_cts_b_io : CTS* (in)  / TDO (out)
  constant PAD_RTS_B                    : natural  := 3; -- uart_rts_b_io : RTS* (out) / TMS (in)
  -- Pad inputs seen by the unselected functions : RX idle (1), CTS* active
  -- (0 : the user UART keeps sending, its firmware never waits on a pad it
  -- does not own), TCK stopped, TDI 1, TMS 1 (the TAPs stay in
  -- Test-Logic-Reset)
  constant PAD_IN_DEFAULT               : std_logic_vector(4-1 downto 0) := (PAD_RX    => '1'
                                                                            ,PAD_TX    => '1'
                                                                            ,PAD_CTS_B => '0'
                                                                            ,PAD_RTS_B => '1');

  signal   mux_sel                      : std_logic_vector(2-1 downto 0);
  signal   pad_sel                      : natural range 0 to NB_FUNC-1;
  signal   pad_func_out                 : pad_array_t(0 to NB_FUNC-1)(4-1 downto 0);
  signal   pad_func_oe                  : pad_array_t(0 to NB_FUNC-1)(4-1 downto 0);
  signal   pad_func_in                  : pad_array_t(0 to NB_FUNC-1)(4-1 downto 0);
  signal   pad_out                      : std_logic_vector(4-1 downto 0);
  signal   pad_oe                       : std_logic_vector(4-1 downto 0);
  signal   pad_in                       : std_logic_vector(4-1 downto 0);
  signal   pad_jtag_ini                 : jtag_ini_t;

  signal   spi_io                       : std_logic_vector(USER_SPI_NB_IO-1 downto 0);

begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- UART PAD
  -- Pad multiplexer (jtag_pad_mux) : the 4 UART pads are given to one
  -- function, selected by debug_mux_sel_i, synchronized on clk :
  --   00 : user UART (RX, TX, CTS*, RTS*)
  --   01 : HWLA UART (TX only : the captures, also on debug_uart_tx_o)
  --   10 : JTAG chain (TCK, TDI, TDO, TMS ; no TRST*)
  --   11 : JTAG over the UART (RX, TX of jtag_bitbang, which drives the
  --        JTAG chain ; CTS* and RTS* not used)
  -- Change debug_mux_sel_i while the functions are idle : the multiplexer has
  -- no clock, and a JTAG scan cut by a change of mode leaves the TAPs in
  -- any state. Switch the FPGA before the cable (terminal or OpenOCD) : two
  -- drivers on TX / TDI and RTS* / TMS otherwise
  -----------------------------------------------------------------------------
  ins_mux_sel_sync1 : sync2dffrn
    port map
    (clk_i                => clk_i
    ,arst_b_i             => arst_b_i
    ,d_i                  => debug_mux_sel_i(0)
    ,q_o                  => mux_sel(0)
    );

  ins_mux_sel_sync2 : sync2dffrn
    port map
    (clk_i                => clk_i
    ,arst_b_i             => arst_b_i
    ,d_i                  => debug_mux_sel_i(1)
    ,q_o                  => mux_sel(1)
    );

  pad_sel <= FUNC_HWLA    when mux_sel = "01" else
             FUNC_JTAG    when mux_sel = "10" else
             FUNC_BITBANG when mux_sel = "11" else
             FUNC_UART;

  -- Pad multiplexer : outputs, output enables and inputs of each function
  -- (with the PAD_* constants, the only place of the pad mapping)
  pad_func_out(FUNC_UART) <= (PAD_TX => uart_tx_i, PAD_RTS_B => uart_rts_b_i, others => '0');
  pad_func_oe (FUNC_UART) <= (PAD_TX => '1'      , PAD_RTS_B => '1'         , others => '0');
  uart_rx_o               <= pad_func_in(FUNC_UART)(PAD_RX   );
  uart_cts_b_o            <= pad_func_in(FUNC_UART)(PAD_CTS_B);

  pad_func_out(FUNC_HWLA) <= (PAD_TX => debug_uart_tx_i, others => '0');
  pad_func_oe (FUNC_HWLA) <= (PAD_TX => '1'            , others => '0');

  pad_func_out(FUNC_JTAG) <= (PAD_CTS_B => jtag_tgt_i.tdo   , others => '0');
  pad_func_oe (FUNC_JTAG) <= (PAD_CTS_B => jtag_tgt_i.tdo_en, others => '0');
  pad_jtag_ini            <= (tck    => pad_func_in(FUNC_JTAG)(PAD_RX   )
                             ,tdi    => pad_func_in(FUNC_JTAG)(PAD_TX   )
                             ,tms    => pad_func_in(FUNC_JTAG)(PAD_RTS_B)
                             ,trst_n => '1');                         -- No TRST* pad

  pad_func_out(FUNC_BITBANG) <= (PAD_TX => bitbang_tx_i, others => '0');
  pad_func_oe (FUNC_BITBANG) <= (PAD_TX => '1'         , others => '0');
  bitbang_rx_o               <= pad_func_in(FUNC_BITBANG)(PAD_RX);

  -- The JTAG chain follows the JTAG pads (10) or jtag_bitbang (11)
  jtag_ini_o                 <= bitbang_jtag_i when pad_sel = FUNC_BITBANG else
                                pad_jtag_ini;

  ins_pad_mux : jtag_pad_mux
    generic map
    (NB_FUNC              => NB_FUNC
    ,NB_PAD               => 4
    ,PAD_IN_DEFAULT       => PAD_IN_DEFAULT
    )
    port map
    (sel_i                => pad_sel
    ,func_out_i           => pad_func_out
    ,func_oe_i            => pad_func_oe
    ,func_in_o            => pad_func_in
    ,pad_out_o            => pad_out
    ,pad_oe_o             => pad_oe
    ,pad_in_i             => pad_in
    );

  pad_in(PAD_RX) <= uart_rx_i;

  PAD_UART_TX : iobuf
    port map
     (buf_io     => uart_tx_io
     ,d_i        => pad_out(PAD_TX)
     ,d_o        => pad_in (PAD_TX)
     ,oe_i       => pad_oe (PAD_TX)
     ,ie_i       => '1'
     );

  PAD_UART_CTS_B : iobuf
    port map
     (buf_io     => uart_cts_b_io
     ,d_i        => pad_out(PAD_CTS_B)
     ,d_o        => pad_in (PAD_CTS_B)
     ,oe_i       => pad_oe (PAD_CTS_B)
     ,ie_i       => '1'
     );

  PAD_UART_RTS_B : iobuf
    port map
     (buf_io     => uart_rts_b_io
     ,d_i        => pad_out(PAD_RTS_B)
     ,d_o        => pad_in (PAD_RTS_B)
     ,oe_i       => pad_oe (PAD_RTS_B)
     ,ie_i       => '1'
     );

  -----------------------------------------------------------------------------
  -- SPI PAD
  -- Only USER_SPI_NB_IO lines have a pad : the other inputs of the SPI are
  -- tied to 0
  -----------------------------------------------------------------------------
  assert USER_SPI_NB_IO <= 8
    report "PicoSoC_pads : USER_SPI_NB_IO ("&integer'image(USER_SPI_NB_IO)&") must be <= 8"
    severity failure;

  PAD_SPI_SCLK : obuf
    port map
     (buf_io     => spi_sclk_io
     ,d_i        => spi_sclk_i
     ,oe_i       => spi_sclk_oe_i
     );

  PAD_SPI_CS_B : obuf
    port map
     (buf_io     => spi_cs_b_io
     ,d_i        => spi_cs_b_i
     ,oe_i       => spi_cs_b_oe_i
     );

  gen_pad_spi_io:
  for i in 0 to USER_SPI_NB_IO-1
  generate
    PAD_SPI_IO : iobuf
      port map
       (buf_io     => spi_io_io   (i)
       ,d_i        => spi_io_i    (i)
       ,d_o        => spi_io      (i)
       ,oe_i       => spi_io_oe_i (i)
       ,ie_i       => '1'
       );
  end generate;

  spi_io_o <= std_logic_vector(resize(unsigned(spi_io),8));

  -----------------------------------------------------------------------------
  -- I2C PAD
  -- Open drain : the line is pulled low when the output enable of the I2C is
  -- set (its output is 0), released ('Z') otherwise : the pull-up of the
  -- board gives the high level
  -----------------------------------------------------------------------------
  PAD_I2C_SCL : iobuf
    port map
     (buf_io     => i2c_scl_io
     ,d_i        => i2c_scl_i
     ,d_o        => i2c_scl_o
     ,oe_i       => i2c_scl_oe_i
     ,ie_i       => '1'
     );

  PAD_I2C_SDA : iobuf
    port map
     (buf_io     => i2c_sda_io
     ,d_i        => i2c_sda_i
     ,d_o        => i2c_sda_o
     ,oe_i       => i2c_sda_oe_i
     ,ie_i       => '1'
     );

end architecture rtl;
