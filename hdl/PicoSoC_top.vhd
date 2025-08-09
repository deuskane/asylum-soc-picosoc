-------------------------------------------------------------------------------
-- Title      : PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : PicoSoC.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2025-01-15
-- Last update: 2025-08-09
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
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library work;
use     work.pbi_pkg.all;
use     work.PicoSoC_pkg.all;

entity PicoSoC_top is
  generic
    (FSYS             : positive := 50_000_000
    ;FSYS_INT         : positive := 50_000_000
    ;BAUD_RATE        : integer  := 115200
    ;UART_DEPTH_TX    : natural  := 0
    ;UART_DEPTH_RX    : natural  := 0
    ;SPI_DEPTH_CMD    : natural  := 0
    ;SPI_DEPTH_TX     : natural  := 0
    ;SPI_DEPTH_RX     : natural  := 0
    ;NB_SWITCH        : positive := 8
    ;NB_LED           : positive := 19
    ;RESET_POLARITY   : string   := "low"       -- "high" / "low"
    ;SUPERVISOR       : boolean  := True 
    ;SAFETY           : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;FAULT_INJECTION  : boolean  := True  
    ;IT_USER_POLARITY : string   := "low"       -- "high" / "low"
    ;FAULT_POLARITY   : string   := "low"       -- "high" / "low"
    ;DEBUG_ENABLE     : boolean  := True 
    );
  port
    (clk_i            : in  std_logic
    ;arst_i           : in  std_logic

    ;switch_i         : in  std_logic_vector(NB_SWITCH-1 downto 0)
    ;led_o            : out std_logic_vector(NB_LED   -1 downto 0)
    ;it_user_i        : in  std_logic

    -- UART Interface
    ;uart_tx_o        : out std_logic
    ;uart_rx_i        : in  std_logic
    ;uart_cts_b_i     : in  std_logic -- Clear   To Send (Active low)
    ;uart_rts_b_o     : out std_logic -- Request To Send (Active low)

    -- SPI Interface
    ;spi_sclk_o       : out std_logic
    ;spi_cs_b_o       : out std_logic
    ;spi_mosi_o       : out std_logic
    ;spi_miso_i       : in  std_logic
     
    -- Error Injection Interface
    ;inject_error_i   : in  std_logic_vector(        3-1 downto 0)

    -- Debug Interface
    ;debug_mux_i      : in  std_logic_vector(        3-1 downto 0)
    ;debug_o          : out std_logic_vector(        8-1 downto 0)
    ;debug_uart_tx_o  : out std_logic
     
    );
end PicoSoC_top;
  
architecture rtl of PicoSoC_top is

  constant TARGET_ADDR_ENCODING         : string   := "one_hot";
  constant ICN_ALGO_SEL                 : string   := "mux";

  constant NB_LED0_USER                 : positive := 8;
  constant NB_LED1_USER                 : positive := 8;
  constant NB_LED_SUPERVISOR            : positive := 3;
  
  signal   clk                          : std_logic;
  signal   arst_b                       : std_logic;
  signal   arst_b_sync                  : std_logic;
  signal   led0_user                    : std_logic_vector(NB_LED0_USER     -1 downto 0);
  signal   led1_user                    : std_logic_vector(NB_LED1_USER     -1 downto 0);
  signal   led_supervisor               : std_logic_vector(NB_LED_SUPERVISOR-1 downto 0);
           
  signal   arst_b_supervisor            : std_logic;
  signal   arst_b_user                  : std_logic_vector(1-1 downto 0);
           
  signal   diff                         : std_logic_vector(3-1 downto 0);
           
  signal   it_user                      : std_logic;
  signal   it_user_sync                 : std_logic;
  signal   inject_error                 : std_logic_vector(3-1 downto 0);

  signal   uart_tx                      : std_logic;
  signal   uart_cts_b                   : std_logic;
  
  signal   debug_mux                    : unsigned        (3-1 downto 0);
  signal   debug_user                   : PicoSoC_user_debug_t      ;
  signal   debug_supervisor             : PicoSoC_supervisor_debug_t;
  
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

  ins_reset_resynchronizer : entity work.sync2dffrn(rtl)
    port map
    (clk_i                => clk_i     
    ,arst_b_i             => arst_b    
    ,d_i                  => '1'       
    ,q_o                  => arst_b_sync
    );

  arst_b_supervisor <= arst_b_sync;

  -----------------------------------------------------------------------------
  -- Clock Management
  -----------------------------------------------------------------------------
  ins_clock_divider : entity work.clock_divider(rtl)
    generic map
    (RATIO                => FSYS/FSYS_INT
    ,ALGO                 => "50%"
     )
    port map
    (clk_i                => clk_i            
    ,arstn_i              => arst_b_supervisor
    ,cke_i                => '1'              
    ,clk_div_o            => clk
     );

  -----------------------------------------------------------------------------
  -- IT_USER User
  -----------------------------------------------------------------------------
  gen_it_user_b:
  if IT_USER_POLARITY = "low"
  generate
    it_user <= not it_user_i;
  end generate gen_it_user_b;

  gen_it_user:
  if IT_USER_POLARITY = "high"
  generate
    it_user <=     it_user_i;
  end generate gen_it_user;
  
  -----------------------------------------------------------------------------
  -- Input synchronization
  -----------------------------------------------------------------------------
  ins_it_user : entity work.sync2dff(rtl)
    port map
    (clk_i                => clk
    ,d_i                  => it_user
    ,q_o                  => it_user_sync
    );

  -----------------------------------------------------------------------------
  -- SoC User
  -----------------------------------------------------------------------------
  ins_soc_user : PicoSoC_user
    generic map
    (CLOCK_FREQ           => FSYS_INT           
    ,BAUD_RATE            => BAUD_RATE          
    ,UART_DEPTH_TX        => UART_DEPTH_TX 
    ,UART_DEPTH_RX        => UART_DEPTH_RX 
    ,SPI_DEPTH_CMD        => SPI_DEPTH_CMD
    ,SPI_DEPTH_TX         => SPI_DEPTH_TX 
    ,SPI_DEPTH_RX         => SPI_DEPTH_RX 
    ,NB_SWITCH            => NB_SWITCH          
    ,NB_LED0              => NB_LED0_USER       
    ,NB_LED1              => NB_LED1_USER       
    ,SAFETY               => SAFETY             
    ,FAULT_INJECTION      => FAULT_INJECTION    
--  ,TARGET_ADDR_ENCODING => TARGET_ADDR_ENCODING
    ,ICN_ALGO_SEL         => ICN_ALGO_SEL        
    )
  port map
    (clk_i                => clk
    ,arst_b_i             => arst_b_user(0)
    ,switch_i             => switch_i
    ,led0_o               => led0_user
    ,led1_o               => led1_user
    ,uart_tx_o            => uart_tx
    ,uart_rx_i            => uart_rx_i
    ,uart_cts_b_i         => uart_cts_b
    ,uart_rts_b_o         => uart_rts_b_o
    ,it_i                 => it_user_sync
    ,diff_o               => diff
    ,inject_error_i       => inject_error
    ,debug_o              => debug_user
    ,spi_sclk_o           => spi_sclk_o 
    ,spi_cs_b_o           => spi_cs_b_o 
    ,spi_mosi_o           => spi_mosi_o 
    ,spi_miso_i           => spi_miso_i 
    );

  uart_tx_o <= uart_tx;
  
  ins_uart_cts_b : entity work.sync2dffrn(rtl)
    port map
    (clk_i                => clk_i     
    ,arst_b_i             => arst_b    
    ,d_i                  => uart_cts_b_i
    ,q_o                  => uart_cts_b
    );
  
  -----------------------------------------------------------------------------
  -- SoC Supervisor
  -----------------------------------------------------------------------------
  gen_supervisor: if SUPERVISOR = True
  generate
    ins_soc_supervisor : PicoSoC_supervisor
      generic map
      (NB_LED0              => 1
      ,NB_LED1              => NB_LED_SUPERVISOR
      ,TARGET_ADDR_ENCODING => TARGET_ADDR_ENCODING
      ,ICN_ALGO_SEL         => ICN_ALGO_SEL        
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
  led_o <= led_supervisor &
           led1_user      &
           led0_user;

  -----------------------------------------------------------------------------
  -- FAULT_INJECTION
  -----------------------------------------------------------------------------
  gen_inject_error_b:
  if FAULT_POLARITY = "low"
  generate
    inject_error <= not inject_error_i;
  end generate gen_inject_error_b;

  gen_inject_error:
  if FAULT_POLARITY = "high"
  generate
    inject_error <=     inject_error_i;
  end generate gen_inject_error;

  -----------------------------------------------------------------------------
  -- Debug
  -----------------------------------------------------------------------------
  gen_debug:
  if DEBUG_ENABLE = True
  generate
    debug_mux      <= unsigned(switch_i(2 downto 0));
    debug_o        <= led0_user                                      when debug_mux = 0 else
                      std_logic_vector(resize(unsigned(switch_i),8)) when debug_mux = 1 else
                      (0      => debug_user      .arst_b,
                       1      => debug_supervisor.arst_b,
                       others => '0')                                when debug_mux = 2 else
                      debug_user.cpu_iaddr(8-1  downto  0)           when debug_mux = 3 else
                      debug_user.cpu_idata(18-1 downto 10)           when debug_mux = 4 else
--                      (7          => debug_user      .cpu_dcs,
--                       6          => debug_user      .cpu_dre,
--                       5          => debug_user      .cpu_dwe,
--                       4          => debug_user      .cpu_dbusy,
--                       3 downto 0 => debug_user      .cpu_daddr(7 downto 4)) when debug_mux = 7 else

                      debug_user      .cpu_dcs   &
                      debug_user      .cpu_dre   &
                      debug_user      .cpu_dwe   &
                      debug_user      .cpu_dbusy &
                      debug_user      .cpu_daddr(7 downto 4)         when debug_mux = 5 else

                      debug_user      .cpu_daddr(7 downto 0)         when debug_mux = 6 else
                      
                      debug_user      .switch_cs   &
                      debug_user      .switch_busy &
                      debug_user      .led0_cs     &
                      debug_user      .led0_busy   &
                      debug_user      .led1_cs     &
                      debug_user      .led1_busy   &
                      debug_user      .uart_cs     &
                      debug_user      .uart_busy                     when debug_mux = 7 else
                      
                      (others => '0');
    debug_uart_tx_o<= uart_tx;
  end generate gen_debug;

  gen_debug_b:
  if DEBUG_ENABLE = False
  generate
    debug_o        <= (others => '0');
    debug_uart_tx_o<= '0';
  end generate gen_debug_b;
    
end architecture rtl;
