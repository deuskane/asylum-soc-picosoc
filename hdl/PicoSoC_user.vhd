-------------------------------------------------------------------------------
-- Title      : PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : PicoSoC.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2025-12-06
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2017 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2017-03-30  1.0      mrosiere Created
-- 2024-12-31  1.1      mrosiere Fix parameter to GPIO
-- 2025-01-12  2.0      mrosiere Add Safety feature
-- 2025-01-15  2.1      mrosiere Update diff detection
-- 2025-01-21  2.2      mrosiere Add UART
-- 2025-04-02  2.3      mrosiere Use ICN
-- 2025-07-15  3.0      mrosiere Add FIFO depth for UART and SPI
-- 2025-11-02  3.1      mrosiere Add Timer
-- 2025-11-27  3.2      mrosiere Add CRC
-- 2025-11-29  3.3      mrosiere Use CRC Generic
-- 2025-11-06  3.4      mrosiere Add Generic LOCK_STEP_DEPTH
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;

-- CSR Package
use     asylum.GPIO_csr_pkg.all;
use     asylum.UART_csr_pkg.all;
use     asylum.SPI_csr_pkg.all;
use     asylum.GIC_csr_pkg.all;
use     asylum.timer_csr_pkg.all;
-- Type Package
use     asylum.sbi_pkg.all;
use     asylum.logic_pkg.all;
-- Modules Packages
use     asylum.PicoSoC_pkg.all;
use     asylum.OpenBlaze8_pkg.all;
use     asylum.gpio_pkg.all;
use     asylum.uart_pkg.all;
use     asylum.spi_pkg.all;
use     asylum.gic_pkg.all;
use     asylum.timer_pkg.all;
use     asylum.icn_pkg.all;

entity PicoSoC_user is
  generic
    (CLOCK_FREQ            : integer  := 50000000
    ;BAUD_RATE             : integer  := 115200
    ;UART_DEPTH_TX         : natural  := 0
    ;UART_DEPTH_RX         : natural  := 0
    ;SPI_DEPTH_CMD         : natural  := 0
    ;SPI_DEPTH_TX          : natural  := 0
    ;SPI_DEPTH_RX          : natural  := 0
    ;NB_SWITCH             : positive := 8
    ;NB_LED0               : positive := 8
    ;NB_LED1               : positive := 8
    ;SAFETY                : string   := "none" -- "none" / "lock-step" / "tmr"
    ;SAFETY                : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;LOCK_STEP_DEPTH       : natural  := 2
    ;FAULT_INJECTION       : boolean  := False
    ;ICN_ALGO_SEL          : string   := "or"
    );
  port
    (clk_i                 : in  std_logic
    ;arst_b_i              : in  std_logic
                          
    ;switch_i              : in  std_logic_vector(NB_SWITCH-1 downto 0)
    ;led0_o                : out std_logic_vector(NB_LED0  -1 downto 0)
    ;led1_o                : out std_logic_vector(NB_LED1  -1 downto 0)

     -- UART Interface
    ;uart_tx_o             : out std_logic
    ;uart_rx_i             : in  std_logic
    ;uart_cts_b_i          : in  std_logic -- Clear   To Send (Active low)
    ;uart_rts_b_o          : out std_logic -- Request To Send (Active low)
                          
    -- SPI Interface
    ;spi_sclk_o            : out std_logic
    ;spi_cs_b_o            : out std_logic
    ;spi_mosi_o            : out std_logic
    ;spi_miso_i            : in  std_logic
                          
    ;it_i                  : in  std_logic
    ;inject_error_i        : in  std_logic_vector(        3-1 downto 0)
    ;diff_o                : out std_logic_vector(        3-1 downto 0) -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0
                                 
    ;debug_o               : out PicoSoC_user_debug_t
    );
end PicoSoC_user;

architecture rtl of PicoSoC_user is

  -- Constant declaration
  constant CST0                       : std_logic_vector (8-1 downto 0) := (others => '0');
  constant CST1                       : std_logic_vector (8-1 downto 0) := (others => '1');

  -- Module parameters
  constant CPU1_ENABLE                : boolean  := ((SAFETY = "lock-step") or
                                                     (SAFETY = "tmr"));
  constant CPU2_ENABLE                : boolean  := ((SAFETY = "tmr"));

  constant LOCK_STEP_DEPTH_INT        : natural  := mux2(SAFETY = "lock-step",LOCK_STEP_DEPTH,0);
  
  -- ICN Configuration
  constant TARGET_ADDR_ENCODING       : string   := PICOSOC_USER_ADDR_ENCODING;
  
  constant TARGET_SWITCH              : integer  := 0;
  constant TARGET_LED0                : integer  := 1;
  constant TARGET_LED1                : integer  := 2;
  constant TARGET_UART                : integer  := 3;
  constant TARGET_SPI                 : integer  := 4;
  constant TARGET_GIC                 : integer  := 5;
  constant TARGET_TIMER               : integer  := 6;
  
  constant NB_TARGET                  : positive := 7;
  
  constant TARGET_ID                  : sbi_addrs_t   (NB_TARGET-1 downto 0) :=
    ( TARGET_SWITCH                   => PICOSOC_USER_SWITCH_BA
     ,TARGET_LED0                     => PICOSOC_USER_LED0_BA  
     ,TARGET_LED1                     => PICOSOC_USER_LED1_BA  
     ,TARGET_UART                     => PICOSOC_USER_UART_BA  
     ,TARGET_SPI                      => PICOSOC_USER_SPI_BA   
     ,TARGET_GIC                      => PICOSOC_USER_GIC_BA   
     ,TARGET_TIMER                    => PICOSOC_USER_TIMER_BA 
      );

  constant TARGET_ADDR_WIDTH          : naturals_t    (NB_TARGET-1 downto 0) :=
    ( TARGET_SWITCH                   => GPIO_ADDR_WIDTH
     ,TARGET_LED0                     => GPIO_ADDR_WIDTH
     ,TARGET_LED1                     => GPIO_ADDR_WIDTH
     ,TARGET_UART                     => UART_ADDR_WIDTH
     ,TARGET_SPI                      => SPI_ADDR_WIDTH
     ,TARGET_GIC                      => GIC_ADDR_WIDTH
     ,TARGET_TIMER                    => TIMER_ADDR_WIDTH
      );
  
  -- Signals ICN
  signal   icn_sbi_inis               : sbi_inis_t(NB_TARGET-1 downto 0)(addr (SBI_ADDR_WIDTH-1 downto 0),
                                                                         wdata(SBI_DATA_WIDTH-1 downto 0));
  signal   icn_sbi_tgts               : sbi_tgts_t(NB_TARGET-1 downto 0)(rdata(SBI_DATA_WIDTH-1 downto 0));

  -- Signals Clock/Reset
  signal   clk                        : std_logic;
  signal   arst_b                     : std_logic;

  -- Signals CPUs
  signal   cpu0_arst_b                : sls_t     (LOCK_STEP_DEPTH_INT downto 0);
  signal   cpu0_ics                   : sls_t     (LOCK_STEP_DEPTH_INT downto 0);
  signal   cpu0_iaddr                 : slvs_t    (LOCK_STEP_DEPTH_INT downto 0)(10-1 downto 0);
  signal   cpu0_idata                 : slvs_t    (LOCK_STEP_DEPTH_INT downto 0)(18-1 downto 0);
  signal   cpu0_sbi_ini               : sbi_inis_t(LOCK_STEP_DEPTH_INT downto 0)(addr (SBI_ADDR_WIDTH-1 downto 0),
                                                                                 wdata(SBI_DATA_WIDTH-1 downto 0));
  signal   cpu0_sbi_tgt               : sbi_tgts_t(LOCK_STEP_DEPTH_INT downto 0)(rdata(SBI_DATA_WIDTH-1 downto 0));
  signal   cpu0_it_val                : sls_t     (LOCK_STEP_DEPTH_INT downto 0);
  signal   cpu0_it_ack                : sls_t     (LOCK_STEP_DEPTH_INT downto 0);

  signal   cpu1_arst_b                : std_logic;
  signal   cpu1_ics                   : std_logic;
  signal   cpu1_iaddr                 : std_logic_vector(10-1 downto 0);
  signal   cpu1_idata                 : std_logic_vector(18-1 downto 0);
  signal   cpu1_sbi_ini               : sbi_ini_t(addr (SBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(SBI_DATA_WIDTH-1 downto 0));
  signal   cpu1_sbi_tgt               : sbi_tgt_t(rdata(SBI_DATA_WIDTH-1 downto 0));
  signal   cpu1_it_val                : std_logic;
  signal   cpu1_it_ack                : std_logic;
  
  signal   cpu2_arst_b                : std_logic;
  signal   cpu2_ics                   : std_logic;
  signal   cpu2_iaddr                 : std_logic_vector(10-1 downto 0);
  signal   cpu2_idata                 : std_logic_vector(18-1 downto 0);
  signal   cpu2_sbi_ini               : sbi_ini_t(addr (SBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(SBI_DATA_WIDTH-1 downto 0));
  signal   cpu2_sbi_tgt               : sbi_tgt_t(rdata(SBI_DATA_WIDTH-1 downto 0));
  signal   cpu2_it_val                : std_logic;
  signal   cpu2_it_ack                : std_logic;

  -- Signals CPU (post lockstep / TMR)
  signal   cpu_ics                    : std_logic;
  signal   cpu_iaddr                  : std_logic_vector(10-1 downto 0);
  signal   cpu_idata                  : std_logic_vector(18-1 downto 0);

  signal   cpu_sbi_ini                : sbi_ini_t(addr (SBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(SBI_DATA_WIDTH-1 downto 0));
  signal   cpu_sbi_tgt                : sbi_tgt_t(rdata(SBI_DATA_WIDTH-1 downto 0));
  signal   cpu_it_val                 : std_logic;
  signal   cpu_it_ack                 : std_logic;

  -- UART
  signal   uart_it                    : std_logic;
  
  -- Interruption Vector
  constant GIC_IT_USER                : natural  := PICOSOC_USER_GIC_IT_USER;
  constant GIC_UART                   : natural  := PICOSOC_USER_GIC_UART   ;
  constant GIC_TIMER                  : natural  := PICOSOC_USER_GIC_TIMER  ;

  constant GIC_WIDTH                  : positive := 3;

  signal   gic_it_vector              : std_logic_vector(GIC_WIDTH-1 downto 0);

  -- Timer
  signal   timer_disable              : std_logic;
  signal   timer_clear                : std_logic;
  signal   timer_it                   : std_logic;
  
  -- Signals Safety

  constant DIFF_CPU0_VS_CPU1          : natural  := PICOSOC_SUPERVISOR_GIC_CPU0_VS_CPU1;
  constant DIFF_CPU1_VS_CPU2          : natural  := PICOSOC_SUPERVISOR_GIC_CPU1_VS_CPU2;
  constant DIFF_CPU2_VS_CPU0          : natural  := PICOSOC_SUPERVISOR_GIC_CPU2_VS_CPU0;

  
  signal   diff                       : std_logic_vector(3-1 downto 0); -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0
  signal   diff_r                     : std_logic_vector(3-1 downto 0); -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0

  signal   cpu0_idata_seu             : std_logic_vector(18-1 downto 0);
  signal   cpu1_idata_seu             : std_logic_vector(18-1 downto 0);
  signal   cpu2_idata_seu             : std_logic_vector(18-1 downto 0);

begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Clock & Reset
  -----------------------------------------------------------------------------
  clk    <= clk_i;
  arst_b <= arst_b_i;
  
  -----------------------------------------------------------------------------
  -- CPU 0
  -----------------------------------------------------------------------------
  ins_sbi_OpenBlaze8_0 : sbi_OpenBlaze8
    generic map
    (RAM_DEPTH            => 256,
     REGFILE_SYNC_READ    => true
     )
    port map
    (clk_i                => clk         
    ,cke_i                => '1'         
    ,arstn_i              => cpu0_arst_b  (0)
    ,ics_o                => cpu0_ics     (0)
    ,iaddr_o              => cpu0_iaddr   (0)
    ,idata_i              => cpu0_idata   (0)
    ,sbi_ini_o            => cpu0_sbi_ini (0)
    ,sbi_tgt_i            => cpu0_sbi_tgt (0)
    ,interrupt_i          => cpu0_it_val  (0)
    ,interrupt_ack_o      => cpu0_it_ack  (0)
    );

  cpu0_arst_b  (0) <= arst_b       ;
  cpu0_idata   (0) <= cpu_idata    ;
  cpu0_sbi_tgt (0) <= cpu_sbi_tgt  ;
  cpu0_it_val  (0) <= cpu_it_val   ;

  -----------------------------------------------------------------------------
  -- CPU ROM
  -----------------------------------------------------------------------------
  ins_sbi_OpenBlaze8_ROM : entity asylum.ROM_user(rom)
    port map
    (clk_i                => clk      
    ,cke_i                => cpu_ics  
    ,address_i            => cpu_iaddr
    ,instruction_o        => cpu_idata
    );

  -----------------------------------------------------------------------------
  -- Interconnect
  -- From 1 Initiator to N Target
  -----------------------------------------------------------------------------
  ins_sbi_icn : sbi_icn
    generic map
    (NB_TARGET            => NB_TARGET
    ,TARGET_ID            => TARGET_ID
    ,TARGET_ADDR_WIDTH    => TARGET_ADDR_WIDTH
    ,TARGET_ADDR_ENCODING => TARGET_ADDR_ENCODING
    ,ALGO_SEL             => ICN_ALGO_SEL
      )
    port map
    (clk_i                => clk      
    ,cke_i                => '1'         
    ,arst_b_i             => arst_b      
    ,sbi_ini_i            => cpu_sbi_ini 
    ,sbi_tgt_o            => cpu_sbi_tgt 
    ,sbi_inis_o           => icn_sbi_inis
    ,sbi_tgts_i           => icn_sbi_tgts
    );

  -----------------------------------------------------------------------------
  -- GPIO 0 - Switch
  -----------------------------------------------------------------------------
  ins_sbi_switch : sbi_GPIO
    generic map
    (NB_IO                => NB_SWITCH
    ,DATA_OE_INIT         => CST0(8-1 downto 0)
    ,IT_ENABLE            => false
    )
    port map
    (clk_i                => clk           
    ,cke_i                => '1'           
    ,arstn_i              => arst_b         
    ,sbi_ini_i            => icn_sbi_inis(TARGET_SWITCH)   
    ,sbi_tgt_o            => icn_sbi_tgts(TARGET_SWITCH)   
    ,data_i               => switch_i      
    ,data_o               => open          
    ,data_oe_o            => open          
    ,interrupt_o          => open          
    ,interrupt_ack_i      => '0'
    );

  -----------------------------------------------------------------------------
  -- GPIO 1 - LED
  -----------------------------------------------------------------------------
  ins_sbi_led0 : sbi_GPIO
    generic map
    (NB_IO                => NB_LED0
    ,DATA_OE_INIT         => CST1(8-1 downto 0)
    ,IT_ENABLE            => false
    )
    port map
    (clk_i                => clk         
    ,cke_i                => '1'         
    ,arstn_i              => arst_b       
    ,sbi_ini_i            => icn_sbi_inis(TARGET_LED0) 
    ,sbi_tgt_o            => icn_sbi_tgts(TARGET_LED0) 
    ,data_i               => X"00"       
    ,data_o               => led0_o      
    ,data_oe_o            => open        
    ,interrupt_o          => open        
    ,interrupt_ack_i      => '0'
    );

  -----------------------------------------------------------------------------
  -- GPIO 2 - LED
  -----------------------------------------------------------------------------
  ins_sbi_led1 : sbi_GPIO
    generic map
    (NB_IO                => NB_LED1
    ,DATA_OE_INIT         => CST1(8-1 downto 0)
    ,IT_ENABLE            => false
    )
    port map
    (clk_i                => clk         
    ,cke_i                => '1'         
    ,arstn_i              => arst_b       
    ,sbi_ini_i            => icn_sbi_inis(TARGET_LED1) 
    ,sbi_tgt_o            => icn_sbi_tgts(TARGET_LED1) 
    ,data_i               => X"00"       
    ,data_o               => led1_o      
    ,data_oe_o            => open        
    ,interrupt_o          => open        
    ,interrupt_ack_i      => '0'
    );

  -----------------------------------------------------------------------------
  -- UART
  -----------------------------------------------------------------------------
  ins_sbi_uart : sbi_uart
    generic map
    (BAUD_RATE            => BAUD_RATE     
    ,CLOCK_FREQ           => CLOCK_FREQ
    ,DEPTH_TX             => UART_DEPTH_TX 
    ,DEPTH_RX             => UART_DEPTH_RX 
     )
    port map
    (clk_i                => clk           
    ,arst_b_i             => arst_b        
    ,sbi_ini_i            => icn_sbi_inis(TARGET_UART)   
    ,sbi_tgt_o            => icn_sbi_tgts(TARGET_UART)   
    ,uart_tx_o            => uart_tx_o     
    ,uart_rx_i            => uart_rx_i
    ,uart_cts_b_i         => uart_cts_b_i
    ,uart_rts_b_o         => uart_rts_b_o
    ,it_o                 => uart_it
    ,debug_o              => debug_o.uart
     );

  -----------------------------------------------------------------------------
  -- SPI
  -----------------------------------------------------------------------------
  ins_sbi_spi : sbi_spi
    generic map
    (USER_DEFINE_PRESCALER=> true
    ,PRESCALER_RATIO      => x"00"
    ,DEPTH_CMD            => SPI_DEPTH_CMD
    ,DEPTH_TX             => SPI_DEPTH_TX 
    ,DEPTH_RX             => SPI_DEPTH_RX 
     )
    port map
    (clk_i                => clk           
    ,arst_b_i             => arst_b        
    ,sbi_ini_i            => icn_sbi_inis(TARGET_SPI)   
    ,sbi_tgt_o            => icn_sbi_tgts(TARGET_SPI)   
    ,sclk_o               => spi_sclk_o   
    ,sclk_oe_o            => open
    ,cs_b_o               => spi_cs_b_o   
    ,cs_b_oe_o            => open
    ,mosi_o               => spi_mosi_o   
    ,mosi_oe_o            => open
    ,miso_i               => spi_miso_i   
     );

  -----------------------------------------------------------------------------
  -- GIC - Interruption Vector
  -----------------------------------------------------------------------------
  gic_it_vector(GIC_IT_USER) <= it_i   ;
  gic_it_vector(GIC_UART   ) <= uart_it;
  gic_it_vector(GIC_TIMER  ) <= timer_it;

  ins_sbi_gic : sbi_GIC
    port map
    (clk_i                => clk         
    ,arst_b_i             => arst_b      
    ,sbi_ini_i            => icn_sbi_inis(TARGET_GIC)
    ,sbi_tgt_o            => icn_sbi_tgts(TARGET_GIC)
    ,its_i                => gic_it_vector
    ,itm_o                => cpu_it_val
    );

  -----------------------------------------------------------------------------
  -- Timer
  -----------------------------------------------------------------------------
  timer_disable <= '0';
  timer_clear   <= '0';

  ins_sbi_timer : sbi_timer
    port map
    (clk_i                => clk         
    ,arst_b_i             => arst_b      
    ,sbi_ini_i            => icn_sbi_inis(TARGET_TIMER)
    ,sbi_tgt_o            => icn_sbi_tgts(TARGET_TIMER)
    ,timer_disable_i      => timer_disable
    ,timer_clear_i        => timer_clear
    ,it_o                 => timer_it
    );

  -----------------------------------------------------------------------------
  -- CPU 0 pipe register
  -----------------------------------------------------------------------------
  gen_cpu0_lockstep_pipe: for i in 1 to LOCK_STEP_DEPTH_INT
  generate
  end generate gen_cpu0_lockstep_pipe;

  -----------------------------------------------------------------------------
  -- CPU 1
  -- diff cpu0 vs cpu1
  -----------------------------------------------------------------------------
  gen_cpu1_enable: if CPU1_ENABLE = true
  generate
  end generate gen_cpu1_enable;

  gen_cpu1_disable: if CPU1_ENABLE = false
  generate
    diff_o(DIFF_CPU0_VS_CPU1) <= '0';
  end generate gen_cpu1_disable;

  -----------------------------------------------------------------------------
  -- CPU 2
  -- diff cpu1 vs cpu2
  -- diff cpu2 vs cpu0
  -----------------------------------------------------------------------------
  gen_cpu2_enable: if CPU2_ENABLE = true
  generate
  end generate gen_cpu2_enable;
  
  gen_cpu2_disable: if CPU2_ENABLE = false
  generate
    diff_o(DIFF_CPU1_VS_CPU2) <= '0';
    diff_o(DIFF_CPU2_VS_CPU0) <= '0';
  end generate gen_cpu2_disable;

  -----------------------------------------------------------------------------
  -- CPU Signals
  --  * ROM interface
  --  * ICN interface
  --  * IT  interface
  --
  -- If safety none or lock-step : take cpu 0
  -- else if tmr : vote all cpu output
  -----------------------------------------------------------------------------
  gen_safety_none    : if SAFETY = "none"
  generate
    cpu_ics        <= cpu0_ics     (0);
    cpu_iaddr      <= cpu0_iaddr   (0);
    cpu_sbi_ini    <= cpu0_sbi_ini (0);
    cpu_it_ack     <= cpu0_it_ack  (0);
  end generate;

  gen_safety_lockstep: if SAFETY = "lock-step"
  generate
  end generate;

  gen_safety_tmr     : if SAFETY = "tmr"
  generate
  end generate;
  
  -----------------------------------------------------------------------------
  -- Fault Injection
  -----------------------------------------------------------------------------
  gen_inject_error_n: if FAULT_INJECTION = false
  generate
  end generate gen_inject_error_n;

  gen_inject_error:   if FAULT_INJECTION = true
  generate
  end generate gen_inject_error;

  -----------------------------------------------------------------------------
  -- Debug
  -----------------------------------------------------------------------------
  debug_o.arst_b      <= arst_b                           ;
  debug_o.cpu_iaddr   <= cpu_iaddr                        ;
  debug_o.cpu_idata   <= cpu_idata                        ;
  debug_o.cpu_dcs     <= cpu_sbi_ini.cs                   ;
  debug_o.cpu_dre     <= cpu_sbi_ini.re                   ;
  debug_o.cpu_dwe     <= cpu_sbi_ini.we                   ;
  debug_o.cpu_daddr   <= cpu_sbi_ini.addr                 ;
  debug_o.cpu_dready  <= cpu_sbi_tgt.ready                ;
  debug_o.switch_cs   <= icn_sbi_inis(TARGET_SWITCH).cs   ;
  debug_o.switch_ready<= icn_sbi_tgts(TARGET_SWITCH).ready;
  debug_o.led0_cs     <= icn_sbi_inis(TARGET_LED0  ).cs   ;
  debug_o.led0_ready  <= icn_sbi_tgts(TARGET_LED0  ).ready;
  debug_o.led1_cs     <= icn_sbi_inis(TARGET_LED1  ).cs   ;
  debug_o.led1_ready  <= icn_sbi_tgts(TARGET_LED1  ).ready;
  debug_o.uart_cs     <= icn_sbi_inis(TARGET_UART  ).cs   ;
  debug_o.uart_ready  <= icn_sbi_tgts(TARGET_UART  ).ready;
  debug_o.spi_cs      <= icn_sbi_inis(TARGET_SPI   ).cs   ;
  debug_o.spi_ready   <= icn_sbi_tgts(TARGET_SPI   ).ready;
    
end architecture rtl;
    
