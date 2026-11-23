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
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.PicoSoC_pkg.all;
use     asylum.techmap_pkg.all;
use     asylum.clock_divider_pkg.all;
use     asylum.hwla_pkg.all;
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
  gen_arst_b:
  if RESET_POLARITY = "low"
  generate
    arst_b <=     arst_i;
  end generate gen_arst_b;

  gen_arst:
  if RESET_POLARITY = "high"
  generate
    arst_b <= not arst_i;
  end generate gen_arst;

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
  gen_it_user_b:
  if USER_IT_POLARITY = "low"
  generate
    it_user <= not it_user_i;
  end generate gen_it_user_b;

  gen_it_user:
  if USER_IT_POLARITY = "high"
  generate
    it_user <=     it_user_i;
  end generate gen_it_user;

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
  gen_inject_error_b:
  if USER_FAULT_POLARITY = "low"
  generate
    inject_error_button <= not inject_error_i;
  end generate gen_inject_error_b;

  gen_inject_error:
  if USER_FAULT_POLARITY = "high"
  generate
    inject_error_button <=     inject_error_i;
  end generate gen_inject_error;

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
  -- Debug : HWLA (logic analyzer) on the bus of the user CPU (cluster 0)
  -- * Trigger : a difference between the redundant CPUs (OR of diff)
  -- * Captures sent byte per byte on debug_uart_tx_o : UART 115200 baud,
  --   8 bits, no parity, 1 stop bit (tools/hwla2vcd.py of asylum-debug-hwla)
  -- * One clock (clk) and the reset of the supervisor : a capture survives
  --   the reset of the user SoC by the supervisor
  -----------------------------------------------------------------------------
  gen_debug: if DEBUG_ENABLE = True
  generate
    -- Baud tick every FSYS_INT/115200 cycles of clk
    constant HWLA_BAUD_TICK_MAX  : std_logic_vector(16-1 downto 0) := std_logic_vector(to_unsigned(FSYS_INT/115200-1, 16));

    -- Probes, from the LSB : data bus (cs, re, we, ready, address, write
    -- data, read data), then instruction bus (address, instruction).
    -- A signal : GHDL 6.0.0 (gcc) crashes on an expression actual of probe_i.
    -- One term per field ('length does not exist on the std_logic fields)
    signal   hwla_probe          : std_logic_vector(debug_user.cpu_idata 'length +
                                                    debug_user.cpu_iaddr 'length +
                                                    debug_user.cpu_drdata'length +
                                                    debug_user.cpu_dwdata'length +
                                                    debug_user.cpu_daddr 'length +
                                                    1 +                             -- cpu_dready
                                                    1 +                             -- cpu_dwe
                                                    1 +                             -- cpu_dre
                                                    1                               -- cpu_dcs
                                                    -1 downto 0);
    signal   hwla_trigger        : std_logic;
    signal   hwla_tdata          : std_logic_vector(8-1 downto 0);
    signal   hwla_tvalid         : std_logic;
    signal   hwla_tready         : std_logic;
    signal   hwla_baud_tick      : std_logic;
  begin
    hwla_probe   <= debug_user.cpu_idata
                  & debug_user.cpu_iaddr
                  & debug_user.cpu_drdata
                  & debug_user.cpu_dwdata
                  & debug_user.cpu_daddr
                  & debug_user.cpu_dready
                  & debug_user.cpu_dwe
                  & debug_user.cpu_dre
                  & debug_user.cpu_dcs;

    hwla_trigger <= '1' when diff /= "000" else
                    '0';

    ins_hwla : hwla
      generic map
      (DEPTH                => 64    -- Small RAM (64 x 72 or 86 bits) : a few tens of instructions
      ,PRE_TRIGGER          => 32    -- Half of the capture before the trigger
      ,TIMESTAMP_WIDTH      => 16    -- A sample at least every 65536 cycles
      ,CHANGE_ONLY          => true  -- A CPU waiting on the bus fills no sample
      ,TDATA_WIDTH          => 8     -- One byte per beat, for the UART
      )
      port map
      (trig_clk_i           => clk
      ,trig_arst_b_i        => arst_b_supervisor
      ,arm_i                => '1'   -- A new capture after each extraction
      ,trigger_i            => hwla_trigger
      ,probe_i              => hwla_probe
      ,armed_o              => open
      ,triggered_o          => open
      ,extract_clk_i        => clk
      ,extract_arst_b_i     => arst_b_supervisor
      ,m_axis_tdata_o       => hwla_tdata
      ,m_axis_tvalid_o      => hwla_tvalid
      ,m_axis_tready_i      => hwla_tready
      ,m_axis_tlast_o       => open
      );

    ins_uart_baud_rate_gen : uart_baud_rate_gen
      generic map
      (BAUD_TICK_CNT_WIDTH     => 16
      )
      port map
      (clk_i                   => clk
      ,arst_b_i                => arst_b_supervisor
      ,baud_tick_en_i          => '1'
      ,baud_tick_o             => hwla_baud_tick
      ,baud_tick_half_o        => open
      ,cfg_baud_tick_cnt_max_i => HWLA_BAUD_TICK_MAX
      );

    -- Transmitter only : no parity, CTS ignored
    ins_uart_tx_axis : uart_tx_axis
      generic map
      (WIDTH                => 8
      )
      port map
      (clk_i                => clk
      ,arst_b_i             => arst_b_supervisor
      ,s_axis_tdata_i       => hwla_tdata
      ,s_axis_tvalid_i      => hwla_tvalid
      ,s_axis_tready_o      => hwla_tready
      ,uart_tx_o            => debug_uart_tx
      ,uart_cts_b_i         => '0'
      ,baud_tick_i          => hwla_baud_tick
      ,parity_enable_i      => '0'
      ,parity_odd_i         => '0'
      ,debug_o              => open
      );
  end generate gen_debug;

  gen_debug_b: if DEBUG_ENABLE = False
  generate
    debug_uart_tx   <= '1';  -- UART idle level
  end generate gen_debug_b;

  -----------------------------------------------------------------------------
  -- Debug : JTAG TAP of fault injection and status, last TAP of the chain
  -- (IDCODE PICOSOC_JTAG_IDCODE_INJECT), its instruction decoder and 2 test
  -- data registers (TCK domain) :
  -- * PICOSOC_JTAG_IR_INJECT : jtag_tdr_inout, 3 bits : writes the error
  --   injection (bit i : CPU i, like inject_error_i), reads diff
  -- * PICOSOC_JTAG_IR_STATUS : jtag_tdr_in, reads (from the LSB) led0_o,
  --   led1_o, led_diff_o, switch_i, then the resets : user SoC, supervisor
  --   SoC (1 : running)
  -- The read values are quasi-static (LEDs, switches, sticky diff, resets) :
  -- sampled directly in Capture-DR, without synchronizer (a value that
  -- changes during the capture may give a mix of old and new bits)
  -- The injection is synchronized on clk (2 flip-flops per bit)
  -----------------------------------------------------------------------------
  gen_debug_jtag: if DEBUG_ENABLE = True
  generate
    signal   inject_ini          : jtag_ini_t;
    signal   inject_tgt          : jtag_tgt_t;
    signal   inject_tck          : std_logic;
    signal   inject_trst_b       : std_logic;
    signal   inject_tlr          : std_logic;
    signal   inject_ir           : std_logic_vector(PICOSOC_JTAG_IR_WIDTH-1 downto 0);
    signal   inject_capture_dr   : std_logic;
    signal   inject_shift_dr     : std_logic;
    signal   inject_update_dr    : std_logic;
    signal   inject_tdi          : std_logic;
    signal   inject_user_tdo_en  : std_logic;
    signal   inject_user_tdo     : std_logic;
    signal   sel_inject          : std_logic;
    signal   sel_status          : std_logic;
    signal   tdo_inject          : std_logic;
    signal   tdo_status          : std_logic;
    signal   inject_tck_domain   : std_logic_vector(3-1 downto 0);
    signal   status              : std_logic_vector(2+USER_NB_SWITCH+3+USER_NB_LED1+USER_NB_LED0-1 downto 0);
  begin
    inject_ini    <= (tck => jtag_ini.tck, tdi => jtag_chain(2).tdo, tms => jtag_ini.tms, trst_n => jtag_ini.trst_n);
    jtag_chain(3) <= (tdo => inject_tgt.tdo, tdo_en => inject_tgt.tdo_en or jtag_chain(2).tdo_en);

    ins_jtag_tap : jtag_tap
      generic map
      (IR_WIDTH             => PICOSOC_JTAG_IR_WIDTH
      ,IDCODE_VALUE         => PICOSOC_JTAG_IDCODE_INJECT
      ,TRST_ENABLE          => false
      )
      port map
      (arst_b_i             => arst_b_supervisor
      ,jtag_ini_i           => inject_ini
      ,jtag_tgt_o           => inject_tgt
      ,tck_o                => inject_tck
      ,trst_b_o             => inject_trst_b
      ,tlr_o                => inject_tlr
      ,ir_o                 => inject_ir
      ,capture_dr_o         => inject_capture_dr
      ,shift_dr_o           => inject_shift_dr
      ,update_dr_o          => inject_update_dr
      ,tdi_o                => inject_tdi
      ,user_tdo_en_i        => inject_user_tdo_en
      ,user_tdo_i           => inject_user_tdo
      );

    -- Instruction decoder
    sel_inject         <= '1' when inject_ir = PICOSOC_JTAG_IR_INJECT else
                          '0';
    sel_status         <= '1' when inject_ir = PICOSOC_JTAG_IR_STATUS else
                          '0';
    inject_user_tdo_en <= sel_inject or sel_status;
    inject_user_tdo    <= tdo_inject when sel_inject = '1' else
                          tdo_status;

    ins_jtag_tdr_inject : jtag_tdr_inout
      port map
      (tck_i                => inject_tck
      ,trst_b_i             => inject_trst_b
      ,tlr_i                => inject_tlr
      ,sel_i                => sel_inject
      ,capture_dr_i         => inject_capture_dr
      ,shift_dr_i           => inject_shift_dr
      ,update_dr_i          => inject_update_dr
      ,tdi_i                => inject_tdi
      ,tdo_o                => tdo_inject
      ,data_i               => diff
      ,data_o               => inject_tck_domain
      );

    status <= arst_b_supervisor_soc & arst_b_user_sync & switch_i & led_supervisor & led1_user & led0_user;

    ins_jtag_tdr_status : jtag_tdr_in
      port map
      (tck_i                => inject_tck
      ,trst_b_i             => inject_trst_b
      ,sel_i                => sel_status
      ,capture_dr_i         => inject_capture_dr
      ,shift_dr_i           => inject_shift_dr
      ,update_dr_i          => inject_update_dr
      ,tdi_i                => inject_tdi
      ,tdo_o                => tdo_status
      ,data_i               => status
      );

    gen_inject_sync: for i in 0 to 3-1
    generate
      ins_inject_sync : sync2dffrn
        port map
        (clk_i              => clk
        ,arst_b_i           => arst_b_supervisor
        ,d_i                => inject_tck_domain(i)
        ,q_o                => inject_error_jtag(i)
        );
    end generate gen_inject_sync;
  end generate gen_debug_jtag;

  gen_debug_jtag_b: if DEBUG_ENABLE = False
  generate
    jtag_chain(3)     <= jtag_chain(2);
    inject_error_jtag <= (others => '0');
  end generate gen_debug_jtag_b;

  debug_uart_tx_o   <= debug_uart_tx;

end architecture rtl;
