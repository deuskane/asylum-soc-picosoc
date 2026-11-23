-------------------------------------------------------------------------------
-- Title      : PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : PicoSoC.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2025-01-15
-- Last update: 2026-09-21
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2017 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2025-01-15  1.0      mrosiere Created
-- 2025-07-15  2.0      mrosiere Add FIFO depth for UART and SPI
-- 2026-10-05  2.1      mrosiere CPU_MODEL default "OpenBlaze8" (was "WardRV", invalid)
-- 2026-11-19  2.2      mrosiere debug_o : LED0 resized to 8 bits (USER_NB_LED0 /= 8)
--                               Document debug_mux_i (unused, kept for pads)
-- 2026-11-21  2.3      mrosiere Reset of the user SoC resynchronized on clk
--                               (2 more cycles : the GPIO input stages are
--                               loaded before the reset release)
-- 2026-11-21  2.4      mrosiere debug_o and debug_mux_i removed (pads freed)
-- 2026-11-21  2.5      mrosiere Add I2C pads
-- 2026-11-21  2.6      mrosiere Add PWM output
-- 2026-11-21  2.7      mrosiere DEBUG_ENABLE : HWLA on the user CPU bus,
--                               captures on debug_uart_tx_o (UART 115200)
-- 2026-11-21  2.8      mrosiere HWLA 3.0.0 (no NB_PROBE) : probe width from
--                               the fields of debug_user
-- 2026-11-22  2.9      mrosiere UART pads shared by the user UART, the HWLA
--                               UART and JTAG (jtag_pad_mux), selected by the
--                               two MSBs of switch_i ; FTDI MPSSE pinout :
--                               uart_tx_io (TDI), uart_cts_b_io (TDO) and
--                               uart_rts_b_io (TMS) become inout pads
-- 2026-11-22  2.10     mrosiere DEBUG_ENABLE : JTAG TAP of fault injection
--                               (ORed with inject_error_i) and status
-- 2026-11-22  2.11     mrosiere USER_CPU_DEBUG_ENABLE,
--                               SUPERVISOR_CPU_DEBUG_ENABLE : debug units of
--                               the user / supervisor CPUs (cpu_wrapper) in
--                               the JTAG chain
-- 2026-11-23  2.12     mrosiere Pads in PicoSoC_pads
-- 2026-11-23  2.13     mrosiere HWLA and its UART in PicoSoC_hwla
-- 2026-11-23  2.14     mrosiere Injection / status TAP in PicoSoC_tap
-- 2026-11-23  2.15     mrosiere cpu_ics in the HWLA probes
-- 2026-11-23  2.16     mrosiere Switches 11 : JTAG over the UART pads
--                               (jtag_bitbang, OpenOCD remote_bitbang,
--                               JTAG_BAUD_RATE) when the chain has a TAP
-- 2026-11-23  2.17     mrosiere Polarities of the inputs with active_high
--                               (one line each)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.PicoSoC_pkg.all;
use     asylum.techmap_pkg.all;
use     asylum.clock_divider_pkg.all;
use     asylum.uart_pkg.all;
use     asylum.jtag_pkg.all;

entity PicoSoC_top is
  generic
    (FSYS                        : positive := 50_000_000
    ;FSYS_INT                    : positive := 50_000_000
    ;RESET_POLARITY              : string   := "low"       -- "high" / "low"
    ;DEBUG_ENABLE                : boolean  := True        -- HWLA, JTAG TAP of fault injection and status
    ;USER_CPU_DEBUG_ENABLE       : boolean  := False       -- Debug unit of the user CPU of every cluster (cpu_wrapper) : TAPs in the JTAG chain
    ;SUPERVISOR_CPU_DEBUG_ENABLE : boolean  := False       -- Debug unit of the supervisor CPU (cpu_wrapper) : its TAP in the JTAG chain
    ;JTAG_BAUD_RATE              : integer  := 115200      -- JTAG over the UART pads (switches 11) : baud rate of the UART of jtag_bitbang
 
    ;CPU_MODEL                   : string   := "OpenBlaze8" -- "OpenBlaze8" / "WardRV_fsm"

    -- USER SoC
    ;USER_NB_CPU                 : natural  := 1
    ;USER_ICN_TARGET_SEL         : string   := "or"
    ;USER_ICN_MASTER_SEL         : string   := "fix"
    ;USER_RAM1_DEPTH             : natural  := 128         -- Up to 128 bytes
    ;USER_RAM2_DEPTH             : natural  := 64          -- Up to 64  bytes
    ;USER_NB_SWITCH              : positive := 8
    ;USER_NB_LED0                : positive := 8
    ;USER_NB_LED1                : positive := 8
    ;USER_BAUD_RATE              : integer  := 115200
    ;USER_UART_DEPTH_TX          : natural  := 0
    ;USER_UART_DEPTH_RX          : natural  := 0
    ;USER_SPI_DEPTH_CMD          : natural  := 0
    ;USER_SPI_DEPTH_TX           : natural  := 0
    ;USER_SPI_DEPTH_RX           : natural  := 0
    ;USER_SPI_NB_IO              : natural  := 8
    ;USER_SAFETY                 : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;USER_LOCK_STEP_DEPTH        : natural  := 2
    ;USER_FAULT_INJECTION        : boolean  := True  
    ;USER_FAULT_POLARITY         : string   := "low"       -- "high" / "low"
    ;USER_IT_POLARITY            : string   := "low"       -- "high" / "low"
    ;USER_MAILBOX_FIFO0_DEPTH_TX : natural  := 4
    ;USER_MAILBOX_FIFO0_DEPTH_RX : natural  := 4
    ;USER_MAILBOX_FIFO1_DEPTH_TX : natural  := 4
    ;USER_MAILBOX_FIFO1_DEPTH_RX : natural  := 4    

    -- SUPERVISOR SoC
    ;SUPERVISOR                  : boolean  := True 
    ;SUPERVISOR_ICN_TARGET_SEL   : string   := "or"
    ;SUPERVISOR_ICN_MASTER_SEL   : string   := "fix"
    ;SUPERVISOR_RAM_DEPTH        : natural  := 128         -- Up to 128 bytes
    );
  port
    (clk_i            : in  std_logic
    ;arst_i           : in  std_logic

    ;switch_i         : in  std_logic_vector(USER_NB_SWITCH-1 downto 0)
    ;led0_o           : out std_logic_vector(USER_NB_LED0  -1 downto 0)
    ;led1_o           : out std_logic_vector(USER_NB_LED1  -1 downto 0)    
    ;led_diff_o       : out std_logic_vector(             3-1 downto 0)
    ;it_user_i        : in  std_logic

    -- UART Interface, shared with the HWLA UART and JTAG (switch_i MSBs) :
    -- UART / JTAG pins of an FTDI MPSSE cable (FT232H, FT2232H)
    ;uart_rx_i        : in    std_logic -- RX   / TCK (FTDI AD0 : TXD  / TCK)
    ;uart_tx_io       : inout std_logic -- TX   / TDI (FTDI AD1 : RXD  / TDI)
    ;uart_cts_b_io    : inout std_logic -- CTS* / TDO (FTDI AD2 : RTS# / TDO), Clear   To Send, active low
    ;uart_rts_b_io    : inout std_logic -- RTS* / TMS (FTDI AD3 : CTS# / TMS), Request To Send, active low

    -- SPI Interface
    ;spi_sclk_io      : inout std_logic
    ;spi_cs_b_io      : inout std_logic
    ;spi_io_io        : inout std_logic_vector(USER_SPI_NB_IO-1 downto 0)

    -- I2C Interface (open drain : external pull-ups)
    ;i2c_scl_io       : inout std_logic
    ;i2c_sda_io       : inout std_logic

    -- PWM Interface
    ;pwm_o            : out std_logic
     
    -- Error Injection Interface
    ;inject_error_i   : in  std_logic_vector(             3-1 downto 0)

    -- Debug Interface
    ;debug_uart_tx_o  : out std_logic -- Captures of the HWLA, UART 115200 8N1 (DEBUG_ENABLE), else 1
     
    );
end PicoSoC_top;
  
architecture rtl of PicoSoC_top is

  constant SUPERVISOR_NB_CPU            : natural  := 1;
  constant SUPERVISOR_NB_LED            : positive := 3;
  
  signal   clk                          : std_logic;
  signal   arst_b                       : std_logic;
  signal   arst_b_sync1                 : std_logic;
  signal   arst_b_sync2                 : std_logic;
  signal   led0_user                    : std_logic_vector(USER_NB_LED0     -1 downto 0);
  signal   led1_user                    : std_logic_vector(USER_NB_LED1     -1 downto 0);
  signal   led_supervisor               : std_logic_vector(SUPERVISOR_NB_LED-1 downto 0);
           
  signal   arst_b_top                   : std_logic;
  signal   arst_b_supervisor            : std_logic;
  signal   arst_b_user                  : std_logic_vector(1-1 downto 0);
  signal   arst_b_user_req              : std_logic;
  signal   arst_b_user_sync             : std_logic;
  signal   arst_b_supervisor_soc        : std_logic;
           
  signal   diff                         : std_logic_vector(3-1 downto 0);
           
  signal   it_user                      : std_logic;
  signal   inject_error                 : std_logic_vector(3-1 downto 0);

  signal   uart_tx                      : std_logic;
  signal   uart_rx                      : std_logic;
  signal   uart_cts_b                   : std_logic;
  signal   uart_rts_b                   : std_logic;

  signal   debug_uart_tx                : std_logic;

  -- JTAG chain : TDI -> user SoC (TAP of the CPU of each cluster) ->
  -- supervisor SoC (TAP of its CPU) -> injection / status TAP -> TDO.
  -- jtag_chain(i) : TDO after the stage i (stage 0 : TDI of the pads) and the
  -- OR of the TDO enables so far. A CPU without debug unit and an absent
  -- stage are wires
  type     jtag_tgts_t                  is array (natural range <>) of jtag_tgt_t;
  signal   jtag_ini                     : jtag_ini_t;
  signal   jtag_chain                   : jtag_tgts_t(0 to 3);
  signal   jtag_tgt                     : jtag_tgt_t;
  signal   user_jtag_ini                : jtag_ini_t;
  signal   user_jtag_tgt                : jtag_tgt_t;
  signal   supervisor_jtag_ini          : jtag_ini_t;
  signal   supervisor_jtag_tgt          : jtag_tgt_t;

  -- ndmreset of the CPU debug units : reset of the SoC of the CPU, not of the
  -- debug unit
  signal   user_ndmreset                : std_logic;
  signal   supervisor_ndmreset          : std_logic;

  -- JTAG over the UART pads (switches 11) : UART of jtag_bitbang, its JTAG
  -- pins (to the chain through PicoSoC_pads). Only with a TAP in the chain
  constant BITBANG_ENABLE               : boolean := DEBUG_ENABLE or USER_CPU_DEBUG_ENABLE or SUPERVISOR_CPU_DEBUG_ENABLE;
  signal   bitbang_rx                   : std_logic;
  signal   bitbang_tx                   : std_logic;
  signal   bitbang_jtag_ini             : jtag_ini_t;

  -- Error injection : push buttons (active high) or JTAG (synchronized on clk)
  signal   inject_error_button          : std_logic_vector(3-1 downto 0);
  signal   inject_error_jtag            : std_logic_vector(3-1 downto 0);
  
  signal   debug_user                   : PicoSoC_user_debug_t      ;
  signal   debug_supervisor             : PicoSoC_supervisor_debug_t;

  signal   spi_sclk_o                   : std_logic;
  signal   spi_sclk_oe_o                : std_logic;
  signal   spi_cs_b_o                   : std_logic;
  signal   spi_cs_b_oe_o                : std_logic;
  signal   spi_io_o_user                : std_logic_vector(8-1 downto 0);
  signal   spi_io_i_user                : std_logic_vector(8-1 downto 0);
  signal   spi_io_oe_o_user             : std_logic_vector(8-1 downto 0);

  signal   i2c_scl_i                    : std_logic;
  signal   i2c_scl_o                    : std_logic;
  signal   i2c_scl_oe_o                 : std_logic;
  signal   i2c_sda_i                    : std_logic;
  signal   i2c_sda_o                    : std_logic;
  signal   i2c_sda_oe_o                 : std_logic;

  signal   pwm                          : std_logic;

begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Reset Management
  -----------------------------------------------------------------------------
  arst_b <= not active_high(arst_i, RESET_POLARITY);

  ins_reset_resynchronizer1 : sync2dffrn
    port map
    (clk_i                => clk_i     
    ,arst_b_i             => arst_b    
    ,d_i                  => '1'       
    ,q_o                  => arst_b_sync1
    );

  ins_reset_resynchronizer2 : sync2dffrn
    port map
    (clk_i                => clk     
    ,arst_b_i             => arst_b_sync1
    ,d_i                  => '1'       
    ,q_o                  => arst_b_sync2
    );

  arst_b_top        <= arst_b_sync1;
  arst_b_supervisor <= arst_b_sync2;

  -----------------------------------------------------------------------------
  -- Clock Management
  -----------------------------------------------------------------------------
  ins_clock_divider : clock_divider
    generic map
    (RATIO                => FSYS/FSYS_INT
    ,ALGO                 => "50%"
     )
    port map
    (clk_i                => clk_i            
    ,arstn_i              => arst_b_top
    ,cke_i                => '1'              
    ,clk_div_o            => clk
     );

  -----------------------------------------------------------------------------
  -- IT_USER User
  -----------------------------------------------------------------------------
  it_user <= active_high(it_user_i, USER_IT_POLARITY);

  -----------------------------------------------------------------------------
  -- SoC User
  -----------------------------------------------------------------------------
  -- The reset of the user SoC (from the supervisor or arst_b_sync2, or
  -- ndmreset of its debugger) is resynchronized on clk : 2 more cycles of
  -- reset with a running clock, so that the registers without reset (input
  -- stages of the GPIOs) are loaded before the reset release
  arst_b_user_req <= arst_b_user(0) and not user_ndmreset;

  ins_reset_resynchronizer_user : sync2dffrn
    port map
    (clk_i                => clk
    ,arst_b_i             => arst_b_user_req
    ,d_i                  => '1'
    ,q_o                  => arst_b_user_sync
    );

  ins_soc_user : PicoSoC_user
    generic map
    (CLOCK_FREQ             => FSYS_INT
    ,CPU_MODEL              => CPU_MODEL
    ,BAUD_RATE              => USER_BAUD_RATE
    ,UART_DEPTH_TX          => USER_UART_DEPTH_TX
    ,UART_DEPTH_RX          => USER_UART_DEPTH_RX
    ,SPI_DEPTH_CMD          => USER_SPI_DEPTH_CMD
    ,SPI_DEPTH_TX           => USER_SPI_DEPTH_TX
    ,SPI_DEPTH_RX           => USER_SPI_DEPTH_RX
    ,NB_SWITCH              => USER_NB_SWITCH
    ,NB_LED0                => USER_NB_LED0
    ,NB_LED1                => USER_NB_LED1
    ,SAFETY                 => USER_SAFETY
    ,LOCK_STEP_DEPTH        => USER_LOCK_STEP_DEPTH
    ,FAULT_INJECTION        => USER_FAULT_INJECTION
    ,ICN_TARGET_SEL         => USER_ICN_TARGET_SEL
    ,NB_CPU                 => USER_NB_CPU
    ,ICN_MASTER_SEL         => USER_ICN_MASTER_SEL
    ,RAM1_DEPTH             => USER_RAM1_DEPTH
    ,RAM2_DEPTH             => USER_RAM2_DEPTH
    ,MAILBOX_FIFO0_DEPTH_TX => USER_MAILBOX_FIFO0_DEPTH_TX
    ,MAILBOX_FIFO0_DEPTH_RX => USER_MAILBOX_FIFO0_DEPTH_RX
    ,MAILBOX_FIFO1_DEPTH_TX => USER_MAILBOX_FIFO1_DEPTH_TX
    ,MAILBOX_FIFO1_DEPTH_RX => USER_MAILBOX_FIFO1_DEPTH_RX
    ,CPU_DEBUG_ENABLE       => USER_CPU_DEBUG_ENABLE
    ,IDCODE_VALUE           => PICOSOC_JTAG_IDCODE_USER_CPU
    )
  port map
    (clk_i                => clk
    ,arst_b_i             => arst_b_user_sync
    ,switch_i             => switch_i
    ,led0_o               => led0_user
    ,led1_o               => led1_user
    ,uart_tx_o            => uart_tx
    ,uart_rx_i            => uart_rx
    ,uart_cts_b_i         => uart_cts_b
    ,uart_rts_b_o         => uart_rts_b
    ,it_i                 => it_user
    ,diff_o               => diff
    ,inject_error_i       => inject_error
    ,debug_o              => debug_user
    ,spi_sclk_o           => spi_sclk_o 
    ,spi_sclk_oe_o        => spi_sclk_oe_o
    ,spi_cs_b_o           => spi_cs_b_o 
    ,spi_cs_b_oe_o        => spi_cs_b_oe_o
    ,spi_io_i             => spi_io_i_user
    ,spi_io_o             => spi_io_o_user
    ,spi_io_oe_o          => spi_io_oe_o_user
    ,i2c_scl_i            => i2c_scl_i
    ,i2c_scl_o            => i2c_scl_o
    ,i2c_scl_oe_o         => i2c_scl_oe_o
    ,i2c_sda_i            => i2c_sda_i
    ,i2c_sda_o            => i2c_sda_o
    ,i2c_sda_oe_o         => i2c_sda_oe_o
    ,pwm_o                => pwm
    ,dbg_arst_b_i         => arst_b_supervisor
    ,jtag_ini_i           => user_jtag_ini
    ,jtag_tgt_o           => user_jtag_tgt
    ,ndmreset_o           => user_ndmreset
    );

  pwm_o        <= pwm;

  -----------------------------------------------------------------------------
  -- SoC Supervisor
  -----------------------------------------------------------------------------
  -- Reset of the supervisor SoC : arst_b_sync2, or ndmreset of its debugger
  arst_b_supervisor_soc <= arst_b_supervisor and not supervisor_ndmreset;

  gen_supervisor: if SUPERVISOR = True
  generate
    ins_soc_supervisor : PicoSoC_supervisor
      generic map
      (CPU_MODEL            => CPU_MODEL     
      ,NB_LED0              => 1
      ,NB_LED1              => SUPERVISOR_NB_LED
      ,ICN_TARGET_SEL       => SUPERVISOR_ICN_TARGET_SEL        
      ,ICN_MASTER_SEL       => SUPERVISOR_ICN_MASTER_SEL
      ,NB_CPU               => SUPERVISOR_NB_CPU
      ,RAM_DEPTH            => SUPERVISOR_RAM_DEPTH
      ,CPU_DEBUG_ENABLE     => SUPERVISOR_CPU_DEBUG_ENABLE
      ,IDCODE_VALUE         => PICOSOC_JTAG_IDCODE_SUPERVISOR_CPU
       )
      port map
      (clk_i                => clk
      ,arst_b_i             => arst_b_supervisor_soc
      ,led0_o               => arst_b_user
      ,led1_o               => led_supervisor
      ,diff_i               => diff 
      ,debug_o              => debug_supervisor
      ,dbg_arst_b_i         => arst_b_supervisor
      ,jtag_ini_i           => supervisor_jtag_ini
      ,jtag_tgt_o           => supervisor_jtag_tgt
      ,ndmreset_o           => supervisor_ndmreset
       );

  end generate gen_supervisor;

  gen_supervisor_n: if SUPERVISOR = False
  generate
    arst_b_user(0)      <= arst_b_supervisor;
    led_supervisor      <= diff;
    debug_supervisor    <= (others => '0');
    supervisor_jtag_tgt <= (tdo => supervisor_jtag_ini.tdi, tdo_en => '0');
    supervisor_ndmreset <= '0';
  end generate gen_supervisor_n;
  
  -----------------------------------------------------------------------------
  -- LED
  -----------------------------------------------------------------------------
  led_diff_o <= led_supervisor;
  led0_o     <= led0_user;
  led1_o     <= led1_user;

  -----------------------------------------------------------------------------
  -- FAULT_INJECTION
  -- Push buttons (polarity USER_FAULT_POLARITY) or JTAG, ORed active high
  -----------------------------------------------------------------------------
  inject_error_button <= active_high(inject_error_i, USER_FAULT_POLARITY);

  inject_error <= inject_error_button or inject_error_jtag;

  -----------------------------------------------------------------------------
  -- Pads : UART pads shared by the user UART, the HWLA UART and the JTAG
  -- chain (selected by the two MSBs of switch_i), SPI and I2C pads
  -----------------------------------------------------------------------------
  ins_pads : PicoSoC_pads
    generic map
    (USER_SPI_NB_IO       => USER_SPI_NB_IO
    )
    port map
    (clk_i                => clk
    ,arst_b_i             => arst_b_supervisor
    ,switch_i             => switch_i(USER_NB_SWITCH-1 downto USER_NB_SWITCH-2)
    ,uart_rx_i            => uart_rx_i
    ,uart_tx_io           => uart_tx_io
    ,uart_cts_b_io        => uart_cts_b_io
    ,uart_rts_b_io        => uart_rts_b_io
    ,spi_sclk_io          => spi_sclk_io
    ,spi_cs_b_io          => spi_cs_b_io
    ,spi_io_io            => spi_io_io
    ,i2c_scl_io           => i2c_scl_io
    ,i2c_sda_io           => i2c_sda_io
    ,uart_tx_i            => uart_tx
    ,uart_rx_o            => uart_rx
    ,uart_cts_b_o         => uart_cts_b
    ,uart_rts_b_i         => uart_rts_b
    ,debug_uart_tx_i      => debug_uart_tx
    ,jtag_ini_o           => jtag_ini
    ,jtag_tgt_i           => jtag_tgt
    ,bitbang_tx_i         => bitbang_tx
    ,bitbang_rx_o         => bitbang_rx
    ,bitbang_jtag_i       => bitbang_jtag_ini
    ,spi_sclk_i           => spi_sclk_o
    ,spi_sclk_oe_i        => spi_sclk_oe_o
    ,spi_cs_b_i           => spi_cs_b_o
    ,spi_cs_b_oe_i        => spi_cs_b_oe_o
    ,spi_io_i             => spi_io_o_user
    ,spi_io_oe_i          => spi_io_oe_o_user
    ,spi_io_o             => spi_io_i_user
    ,i2c_scl_i            => i2c_scl_o
    ,i2c_scl_oe_i         => i2c_scl_oe_o
    ,i2c_scl_o            => i2c_scl_i
    ,i2c_sda_i            => i2c_sda_o
    ,i2c_sda_oe_i         => i2c_sda_oe_o
    ,i2c_sda_o            => i2c_sda_i
    );

  -----------------------------------------------------------------------------
  -- JTAG over the UART pads (switches 11) : jtag_bitbang of asylum-debug-jtag
  -- behind a UART (8 data bits, no parity, 1 stop bit, JTAG_BAUD_RATE) :
  -- OpenOCD (remote_bitbang adapter, socat to the serial port) sends one
  -- byte per change of TCK / TMS / TDI and one per TDO read ('R'),
  -- jtag_bitbang answers '0' / '1'. Its JTAG pins drive the JTAG chain in
  -- place of the JTAG pads (PicoSoC_pads) ; SRST ('s', 'u') is not
  -- connected (reset a CPU with ndmreset of its debug unit) ; TRST* ('t',
  -- 'u') reaches the TAPs, which ignore it (no TRST*) ; the LED of OpenOCD
  -- (blink) is not used (no free LED).
  -- Clock and reset of the supervisor : a reset of the user SoC keeps the
  -- link. TCK is a register of clk : a clock derived from data for the TAPs
  -- (see the README for the constraints).
  -- Only with a TAP in the chain : else the TX pad stays idle (1) and the
  -- chain sees TCK 0, TMS 1
  -----------------------------------------------------------------------------
  gen_bitbang: if BITBANG_ENABLE
  generate
    -- Baud tick every FSYS_INT/JTAG_BAUD_RATE cycles of clk
    constant BITBANG_BAUD_TICK_MAX : std_logic_vector(16-1 downto 0) := std_logic_vector(to_unsigned(FSYS_INT/JTAG_BAUD_RATE-1, 16));

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
  begin
    -- RX synchronized on clk (uart_rx_axis expects a synchronous input).
    -- sync2dffrn is reset to '0' : the inverted line is synchronized, so
    -- that RX is idle ('1') during the reset
    rx_b    <= not bitbang_rx;

    ins_bitbang_rx_sync : sync2dffrn
      port map
      (clk_i                   => clk
      ,arst_b_i                => arst_b_supervisor
      ,d_i                     => rx_b
      ,q_o                     => rx_b_sync
      );

    rx_sync <= not rx_b_sync;

    ins_bitbang_rx_baud : uart_baud_rate_gen
      generic map
      (BAUD_TICK_CNT_WIDTH     => 16
      )
      port map
      (clk_i                   => clk
      ,arst_b_i                => arst_b_supervisor
      ,baud_tick_en_i          => rx_tick_en
      ,baud_tick_o             => rx_tick
      ,baud_tick_half_o        => rx_tick_half
      ,cfg_baud_tick_cnt_max_i => BITBANG_BAUD_TICK_MAX
      );

    ins_bitbang_rx : uart_rx_axis
      generic map
      (WIDTH                   => 8
      )
      port map
      (clk_i                   => clk
      ,arst_b_i                => arst_b_supervisor
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
      (clk_i                   => clk
      ,arst_b_i                => arst_b_supervisor
      ,s_axis_tdata_i          => cmd_tdata
      ,s_axis_tvalid_i         => cmd_tvalid
      ,s_axis_tready_o         => cmd_tready
      ,m_axis_tdata_o          => answer_tdata
      ,m_axis_tvalid_o         => answer_tvalid
      ,m_axis_tready_i         => answer_tready
      ,jtag_ini_o              => bitbang_jtag_ini
      ,jtag_tgt_i              => jtag_tgt
      ,srst_o                  => open
      ,blink_o                 => open
      );

    ins_bitbang_tx_baud : uart_baud_rate_gen
      generic map
      (BAUD_TICK_CNT_WIDTH     => 16
      )
      port map
      (clk_i                   => clk
      ,arst_b_i                => arst_b_supervisor
      ,baud_tick_en_i          => '1'
      ,baud_tick_o             => tx_tick
      ,baud_tick_half_o        => open
      ,cfg_baud_tick_cnt_max_i => BITBANG_BAUD_TICK_MAX
      );

    ins_bitbang_tx : uart_tx_axis
      generic map
      (WIDTH                   => 8
      )
      port map
      (clk_i                   => clk
      ,arst_b_i                => arst_b_supervisor
      ,s_axis_tdata_i          => answer_tdata
      ,s_axis_tvalid_i         => answer_tvalid
      ,s_axis_tready_o         => answer_tready
      ,uart_tx_o               => bitbang_tx
      ,uart_cts_b_i            => '0'
      ,baud_tick_i             => tx_tick
      ,parity_enable_i         => '0'
      ,parity_odd_i            => '0'
      ,debug_o                 => open
      );
  end generate gen_bitbang;

  gen_bitbang_b: if not BITBANG_ENABLE
  generate
    bitbang_tx       <= '1';                                              -- UART idle level
    bitbang_jtag_ini <= (tck => '0', tms => '1', tdi => '1', trst_n => '1'); -- No TAP to drive
  end generate gen_bitbang_b;

  -----------------------------------------------------------------------------
  -- JTAG chain
  -- TDI -> user SoC -> supervisor SoC -> injection / status TAP -> TDO. The
  -- TAPs share TCK and TMS (they are in the same state) : TDO from the last
  -- stage, its enable is the OR of the enables of the stages. The CPU debug
  -- units are in cpu_wrapper (USER_CPU_DEBUG_ENABLE,
  -- SUPERVISOR_CPU_DEBUG_ENABLE) : power-on reset arst_b_supervisor (a reset
  -- of the SoC of the CPU does not reset its debug unit)
  -----------------------------------------------------------------------------
  jtag_chain(0)       <= (tdo => jtag_ini.tdi, tdo_en => '0');

  user_jtag_ini       <= (tck => jtag_ini.tck, trst_n => jtag_ini.trst_n, tms => jtag_ini.tms, tdi => jtag_chain(0).tdo);
  jtag_chain(1)       <= (tdo => user_jtag_tgt.tdo, tdo_en => user_jtag_tgt.tdo_en or jtag_chain(0).tdo_en);

  supervisor_jtag_ini <= (tck => jtag_ini.tck, trst_n => jtag_ini.trst_n, tms => jtag_ini.tms, tdi => jtag_chain(1).tdo);
  jtag_chain(2)       <= (tdo => supervisor_jtag_tgt.tdo, tdo_en => supervisor_jtag_tgt.tdo_en or jtag_chain(1).tdo_en);

  jtag_tgt            <= jtag_chain(3);

  assert (not (USER_CPU_DEBUG_ENABLE or SUPERVISOR_CPU_DEBUG_ENABLE) or CPU_MODEL = "WardRV_fsm")
    report "PicoSoC_top : USER_CPU_DEBUG_ENABLE and SUPERVISOR_CPU_DEBUG_ENABLE need CPU_MODEL WardRV_fsm (" & CPU_MODEL & ")"
    severity failure;

  assert (not SUPERVISOR_CPU_DEBUG_ENABLE or SUPERVISOR)
    report "PicoSoC_top : SUPERVISOR_CPU_DEBUG_ENABLE needs SUPERVISOR"
    severity failure;

  -----------------------------------------------------------------------------
  -- Debug : HWLA (logic analyzer) on the bus of the user CPU (cluster 0),
  -- in PicoSoC_hwla
  -- * Trigger : a difference between the redundant CPUs (OR of diff)
  -- * Captures sent byte per byte on debug_uart_tx_o : UART 115200 baud,
  --   8 bits, no parity, 1 stop bit (tools/hwla2vcd.py of asylum-debug-hwla)
  -- * One clock (clk) and the reset of the supervisor : a capture survives
  --   the reset of the user SoC by the supervisor
  -----------------------------------------------------------------------------
  gen_debug: if DEBUG_ENABLE = True
  generate
    -- Probes, from the LSB : data bus (cs, re, we, ready, address, write
    -- data, read data), then instruction bus (fetch strobe ics, address,
    -- instruction).
    -- A signal : GHDL 6.0.0 (gcc) crashes on an expression actual of probe_i.
    -- One term per field ('length does not exist on the std_logic fields)
    signal   hwla_probe          : std_logic_vector(debug_user.cpu_idata 'length +
                                                    debug_user.cpu_iaddr 'length +
                                                    1 +                             -- cpu_ics
                                                    debug_user.cpu_drdata'length +
                                                    debug_user.cpu_dwdata'length +
                                                    debug_user.cpu_daddr 'length +
                                                    1 +                             -- cpu_dready
                                                    1 +                             -- cpu_dwe
                                                    1 +                             -- cpu_dre
                                                    1                               -- cpu_dcs
                                                    -1 downto 0);
    signal   hwla_trigger        : std_logic;
  begin
    hwla_probe   <= debug_user.cpu_idata
                  & debug_user.cpu_iaddr
                  & debug_user.cpu_ics
                  & debug_user.cpu_drdata
                  & debug_user.cpu_dwdata
                  & debug_user.cpu_daddr
                  & debug_user.cpu_dready
                  & debug_user.cpu_dwe
                  & debug_user.cpu_dre
                  & debug_user.cpu_dcs;

    hwla_trigger <= '1' when diff /= "000" else
                    '0';

    ins_hwla : PicoSoC_hwla
      generic map
      (FSYS_INT             => FSYS_INT
      )
      port map
      (clk_i                => clk
      ,arst_b_i             => arst_b_supervisor
      ,probe_i              => hwla_probe
      ,trigger_i            => hwla_trigger
      ,uart_tx_o            => debug_uart_tx
      );
  end generate gen_debug;

  gen_debug_b: if DEBUG_ENABLE = False
  generate
    debug_uart_tx   <= '1';  -- UART idle level
  end generate gen_debug_b;

  -----------------------------------------------------------------------------
  -- Debug : JTAG TAP of fault injection and status, last TAP of the chain,
  -- in PicoSoC_tap (IDCODE PICOSOC_JTAG_IDCODE_INJECT, TCK domain) :
  -- * PICOSOC_JTAG_IR_INJECT : writes the error injection (bit i : CPU i,
  --   like inject_error_i, synchronized on clk), reads diff
  -- * PICOSOC_JTAG_IR_STATUS : reads (from the LSB) led0_o, led1_o,
  --   led_diff_o, switch_i, then the resets : user SoC, supervisor SoC
  --   (1 : running)
  -----------------------------------------------------------------------------
  gen_debug_jtag: if DEBUG_ENABLE = True
  generate
    signal   inject_ini          : jtag_ini_t;
    signal   inject_tgt          : jtag_tgt_t;
    -- A signal : GHDL 6.0.0 crashes on an expression actual of status_i
    signal   status              : std_logic_vector(2+USER_NB_SWITCH+3+USER_NB_LED1+USER_NB_LED0-1 downto 0);
  begin
    inject_ini    <= (tck => jtag_ini.tck, tdi => jtag_chain(2).tdo, tms => jtag_ini.tms, trst_n => jtag_ini.trst_n);
    jtag_chain(3) <= (tdo => inject_tgt.tdo, tdo_en => inject_tgt.tdo_en or jtag_chain(2).tdo_en);

    status <= arst_b_supervisor_soc & arst_b_user_sync & switch_i & led_supervisor & led1_user & led0_user;

    ins_tap : PicoSoC_tap
      port map
      (clk_i                => clk
      ,arst_b_i             => arst_b_supervisor
      ,jtag_ini_i           => inject_ini
      ,jtag_tgt_o           => inject_tgt
      ,diff_i               => diff
      ,status_i             => status
      ,inject_error_o       => inject_error_jtag
      );
  end generate gen_debug_jtag;

  gen_debug_jtag_b: if DEBUG_ENABLE = False
  generate
    jtag_chain(3)     <= jtag_chain(2);
    inject_error_jtag <= (others => '0');
  end generate gen_debug_jtag_b;

  debug_uart_tx_o   <= debug_uart_tx;

end architecture rtl;
