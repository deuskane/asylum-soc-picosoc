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
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.PicoSoC_pkg.all;
use     asylum.techmap_pkg.all;
use     asylum.clock_divider_pkg.all;

entity PicoSoC_top is
  generic
    (FSYS                        : positive := 50_000_000
    ;FSYS_INT                    : positive := 50_000_000
    ;RESET_POLARITY              : string   := "low"       -- "high" / "low"
    ;DEBUG_ENABLE                : boolean  := True
 
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

    -- UART Interface
    ;uart_tx_o        : out std_logic
    ;uart_rx_i        : in  std_logic
    ;uart_cts_b_i     : in  std_logic -- Clear   To Send (Active low)
    ;uart_rts_b_o     : out std_logic -- Request To Send (Active low)

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
    ;debug_uart_tx_o  : out std_logic -- Copy of uart_tx_o (DEBUG_ENABLE), else 0
     
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
  signal   arst_b_user_sync             : std_logic;
           
  signal   diff                         : std_logic_vector(3-1 downto 0);
           
  signal   it_user                      : std_logic;
  signal   inject_error                 : std_logic_vector(3-1 downto 0);

  signal   uart_tx                      : std_logic;
  signal   uart_rx                      : std_logic;
  signal   uart_cts_b                   : std_logic;
  signal   uart_rts_b                   : std_logic;
  
  signal   debug_user                   : PicoSoC_user_debug_t      ;
  signal   debug_supervisor             : PicoSoC_supervisor_debug_t;

  signal   spi_sclk_o                   : std_logic;
  signal   spi_sclk_oe_o                : std_logic;
  signal   spi_cs_b_o                   : std_logic;
  signal   spi_cs_b_oe_o                : std_logic;
  signal   spi_io_o                     : std_logic_vector(USER_SPI_NB_IO-1 downto 0);
  signal   spi_io_i                     : std_logic_vector(USER_SPI_NB_IO-1 downto 0);
  signal   spi_io_oe_o                  : std_logic_vector(USER_SPI_NB_IO-1 downto 0);
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
  -- The reset of the user SoC (from the supervisor or arst_b_sync2) is
  -- resynchronized on clk : 2 more cycles of reset with a running clock, so
  -- that the registers without reset (input stages of the GPIOs) are loaded
  -- before the reset release
  ins_reset_resynchronizer_user : sync2dffrn
    port map
    (clk_i                => clk
    ,arst_b_i             => arst_b_user(0)
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
    );

  spi_io_o     <= spi_io_o_user   (spi_io_o   'range);
  spi_io_oe_o  <= spi_io_oe_o_user(spi_io_oe_o'range);
  -- Only USER_SPI_NB_IO lines have a pad : the other inputs of the SPI are tied to 0
  spi_io_i_user<= std_logic_vector(resize(unsigned(spi_io_i),8));

  assert USER_SPI_NB_IO <= 8
    report "PicoSoC_top : USER_SPI_NB_IO ("&integer'image(USER_SPI_NB_IO)&") must be <= 8"
    severity failure;

  uart_tx_o    <= uart_tx     ;
  uart_rx      <= uart_rx_i   ;
  uart_rts_b_o <= uart_rts_b  ;
  uart_cts_b   <= uart_cts_b_i;

  pwm_o        <= pwm;

  -----------------------------------------------------------------------------
  -- SoC Supervisor
  -----------------------------------------------------------------------------
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
       )
      port map
      (clk_i                => clk
      ,arst_b_i             => arst_b_supervisor
      ,led0_o               => arst_b_user
      ,led1_o               => led_supervisor
      ,diff_i               => diff 
      ,debug_o              => debug_supervisor
       );

  end generate gen_supervisor;

  gen_supervisor_n: if SUPERVISOR = False
  generate
    arst_b_user(0)   <= arst_b_supervisor;
    led_supervisor   <= diff;
    debug_supervisor <= (others => '0');
  end generate gen_supervisor_n;
  
  -----------------------------------------------------------------------------
  -- LED
  -----------------------------------------------------------------------------
  led_diff_o <= led_supervisor;
  led0_o     <= led0_user;
  led1_o     <= led1_user;

  -----------------------------------------------------------------------------
  -- FAULT_INJECTION
  -----------------------------------------------------------------------------
  gen_inject_error_b:
  if USER_FAULT_POLARITY = "low"
  generate
    inject_error <= not inject_error_i;
  end generate gen_inject_error_b;

  gen_inject_error:
  if USER_FAULT_POLARITY = "high"
  generate
    inject_error <=     inject_error_i;
  end generate gen_inject_error;

  -----------------------------------------------------------------------------
  -- SPI PAD
  -----------------------------------------------------------------------------
  PAD_SPI_SCLK : obuf
    port map
     (buf_io     => spi_sclk_io
     ,d_i        => spi_sclk_o
     ,oe_i       => spi_sclk_oe_o
     );

  PAD_SPI_CS_B : obuf
    port map
     (buf_io     => spi_cs_b_io
     ,d_i        => spi_cs_b_o
     ,oe_i       => spi_cs_b_oe_o
     );

  gen_pad_spi_io:
  for i in 0 to USER_SPI_NB_IO-1 
  generate
    PAD_SPI_IO : iobuf
      port map
       (buf_io     => spi_io_io   (i)
       ,d_i        => spi_io_o    (i)
       ,d_o        => spi_io_i    (i)
       ,oe_i       => spi_io_oe_o (i)
       ,ie_i       => '1'
       );
  end generate;

  -----------------------------------------------------------------------------
  -- I2C PAD
  -- Open drain : the line is pulled low when the output enable of the I2C is
  -- set (its output is 0), released ('Z') otherwise : the pull-up of the
  -- board gives the high level
  -----------------------------------------------------------------------------
  PAD_I2C_SCL : iobuf
    port map
     (buf_io     => i2c_scl_io
     ,d_i        => i2c_scl_o
     ,d_o        => i2c_scl_i
     ,oe_i       => i2c_scl_oe_o
     ,ie_i       => '1'
     );

  PAD_I2C_SDA : iobuf
    port map
     (buf_io     => i2c_sda_io
     ,d_i        => i2c_sda_o
     ,d_o        => i2c_sda_i
     ,oe_i       => i2c_sda_oe_o
     ,ie_i       => '1'
     );

  -----------------------------------------------------------------------------
  -- Debug
  -----------------------------------------------------------------------------
  -- Copy of the UART output on a second pad (e.g. to a logic analyzer)
  debug_uart_tx_o <= uart_tx when DEBUG_ENABLE = True else
                     '0';
    
end architecture rtl;
