-------------------------------------------------------------------------------
-- Title      : PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : PicoSoC.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2026-05-25
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
-- 2026-05-06  3.5      mrosiere Add Generic CPU_MODEL
-- 2026-05-16  3.6      mrosiere Add RAM
-- 2026-05-25  3.7      mrosiere Add Spinlock and mailbox
-- 2026-06-17  3.8      mrosiere Add RAM2
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;

-- Type Package
use     asylum.sbi_pkg.all;
use     asylum.logic_pkg.all;
use     asylum.math_pkg.all;
-- CSR Package
use     asylum.GPIO_csr_pkg.all;
use     asylum.UART_csr_pkg.all;
use     asylum.SPI_csr_pkg.all;
use     asylum.GIC_csr_pkg.all;
use     asylum.timer_csr_pkg.all;
use     asylum.crc_csr_pkg.all;
use     asylum.spinlock_csr_pkg.all;
use     asylum.mailbox_csr_pkg.all;
-- Modules Packages
use     asylum.PicoSoC_pkg.all;
use     asylum.gpio_pkg.all;
use     asylum.uart_pkg.all;
use     asylum.spi_pkg.all;
use     asylum.gic_pkg.all;
use     asylum.timer_pkg.all;
use     asylum.crc_pkg.all;
use     asylum.spinlock_pkg.all;
use     asylum.mailbox_pkg.all;
use     asylum.icn_pkg.all;
use     asylum.ram_pkg.all;
use     asylum.ROM_user_pkg.all;

entity PicoSoC_user is
  generic
    (CLOCK_FREQ             : integer  := 50000000
    ;BAUD_RATE              : integer  := 115200
    ;UART_DEPTH_TX          : natural  := 0
    ;UART_DEPTH_RX          : natural  := 0
    ;SPI_DEPTH_CMD          : natural  := 0
    ;SPI_DEPTH_TX           : natural  := 0
    ;SPI_DEPTH_RX           : natural  := 0
    ;NB_SWITCH              : positive := 8
    ;NB_LED0                : positive := 8
    ;NB_LED1                : positive := 8
    ;SAFETY                 : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;LOCK_STEP_DEPTH        : natural  := 2
    ;FAULT_INJECTION        : boolean  := False
    ;ICN_TARGET_SEL         : string   := "or"
    ;ICN_MASTER_SEL         : string   := "fix"
    ;NB_CPU                 : natural  := 1
    ;CPU_MODEL              : string   := "OpenBlaze8"
    ;RAM1_DEPTH             : natural  := 128
    ;RAM2_DEPTH             : natural  := 64
    ;MAILBOX_FIFO0_DEPTH_TX : natural  := 4
    ;MAILBOX_FIFO0_DEPTH_RX : natural  := 4
    ;MAILBOX_FIFO1_DEPTH_TX : natural  := 4
    ;MAILBOX_FIFO1_DEPTH_RX : natural  := 4
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

  -- CPU parameters
  constant CPU_IMEM_ADDR_WIDTH        : positive := ROM_user_ADDR_WIDTH;
  constant CPU_IMEM_DATA_WIDTH        : positive := ROM_user_DATA_WIDTH;
  constant CPU_DMEM_ADDR_WIDTH        : positive := SBI_ADDR_WIDTH;
  constant CPU_DMEM_DATA_WIDTH        : positive := SBI_DATA_WIDTH;

  -- ICN1 (CPU) Configuration
  constant ICN1_NB_MASTER             : positive := 1;

  constant ICN1_TARGET_ADDR_ENCODING  : string   := PICOSOC_USER_ADDR_ENCODING;
  
  constant ICN1_TARGET_GIC            : integer  := 0;
  constant ICN1_TARGET_RAM1           : integer  := 1;
  constant ICN1_TARGET_ICN2           : integer  := 2;
  
  constant ICN1_NB_TARGET             : positive := 3; -- For default target, add 1 to the number of targets
  
  constant ICN1_TARGET_ID             : sbi_addrs_t   (ICN1_NB_TARGET-1 downto 0) :=
    ( ICN1_TARGET_GIC                 => PICOSOC_USER_GIC_BA   
     ,ICN1_TARGET_RAM1                => PICOSOC_USER_RAM1_BA
     ,ICN1_TARGET_ICN2                => CST0
      );

  constant ICN1_TARGET_ADDR_WIDTH     : naturals_t    (ICN1_NB_TARGET-1 downto 0) :=
    ( ICN1_TARGET_GIC                 => GIC_ADDR_WIDTH
     ,ICN1_TARGET_RAM1                => log2(RAM1_DEPTH)
     ,ICN1_TARGET_ICN2                => CPU_DMEM_DATA_WIDTH
      );

  -- ICN2 (System) Configuration
  constant ICN2_NB_MASTER             : positive := NB_CPU;

  constant ICN2_TARGET_ADDR_ENCODING  : string   := PICOSOC_USER_ADDR_ENCODING;
  
  constant ICN2_TARGET_SWITCH         : integer  := 0;
  constant ICN2_TARGET_LED0           : integer  := 1;
  constant ICN2_TARGET_LED1           : integer  := 2;
  constant ICN2_TARGET_UART           : integer  := 3;
  constant ICN2_TARGET_SPI            : integer  := 4;
  constant ICN2_TARGET_TIMER          : integer  := 5;
  constant ICN2_TARGET_CRC            : integer  := 6;
  constant ICN2_TARGET_SPINLOCK       : integer  := 7;
  constant ICN2_TARGET_MAILBOX        : integer  := 8;
  constant ICN2_TARGET_RAM2           : integer  := 9;
  
  constant ICN2_NB_TARGET             : positive := 10;
  
  constant ICN2_TARGET_ID             : sbi_addrs_t   (ICN2_NB_TARGET-1 downto 0) :=
    ( ICN2_TARGET_SWITCH              => PICOSOC_USER_SWITCH_BA
     ,ICN2_TARGET_LED0                => PICOSOC_USER_LED0_BA  
     ,ICN2_TARGET_LED1                => PICOSOC_USER_LED1_BA  
     ,ICN2_TARGET_UART                => PICOSOC_USER_UART_BA  
     ,ICN2_TARGET_SPI                 => PICOSOC_USER_SPI_BA   
     ,ICN2_TARGET_TIMER               => PICOSOC_USER_TIMER_BA 
     ,ICN2_TARGET_CRC                 => PICOSOC_USER_CRC_BA   
     ,ICN2_TARGET_SPINLOCK            => PICOSOC_USER_SPINLOCK_BA
     ,ICN2_TARGET_MAILBOX             => PICOSOC_USER_MAILBOX_BA
     ,ICN2_TARGET_RAM2                => PICOSOC_USER_RAM2_BA
      );

  constant ICN2_TARGET_ADDR_WIDTH     : naturals_t    (ICN2_NB_TARGET-1 downto 0) :=
    ( ICN2_TARGET_SWITCH              => GPIO_ADDR_WIDTH
     ,ICN2_TARGET_LED0                => GPIO_ADDR_WIDTH
     ,ICN2_TARGET_LED1                => GPIO_ADDR_WIDTH
     ,ICN2_TARGET_UART                => UART_ADDR_WIDTH
     ,ICN2_TARGET_SPI                 => SPI_ADDR_WIDTH
     ,ICN2_TARGET_TIMER               => TIMER_ADDR_WIDTH
     ,ICN2_TARGET_CRC                 => CRC_ADDR_WIDTH
     ,ICN2_TARGET_SPINLOCK            => SPINLOCK_ADDR_WIDTH
     ,ICN2_TARGET_MAILBOX             => MAILBOX_ADDR_WIDTH
     ,ICN2_TARGET_RAM2                => log2(RAM2_DEPTH)
      );
  
  -- Signals ICN2 - System
  signal   icn2_sbi_inim              : sbi_inis_t(ICN2_NB_MASTER-1 downto 0)(addr (CPU_DMEM_ADDR_WIDTH-1 downto 0),
                                                                              wdata(CPU_DMEM_DATA_WIDTH-1 downto 0));
  signal   icn2_sbi_tgtm              : sbi_tgts_t(ICN2_NB_MASTER-1 downto 0)(rdata(CPU_DMEM_DATA_WIDTH-1 downto 0));

  signal   icn2_sbi_inis              : sbi_inis_t(ICN2_NB_TARGET-1 downto 0)(addr (CPU_DMEM_ADDR_WIDTH-1 downto 0),
                                                                              wdata(CPU_DMEM_DATA_WIDTH-1 downto 0));
  signal   icn2_sbi_tgts              : sbi_tgts_t(ICN2_NB_TARGET-1 downto 0)(rdata(CPU_DMEM_DATA_WIDTH-1 downto 0));

  -- Signals Clock/Reset
  signal   clk                        : std_logic;
  signal   arst_b                     : std_logic;

  -- UART
  signal   uart_it                    : std_logic;
  
  -- Interruption Vector
  constant GIC_IT_USER                : natural  := PICOSOC_USER_GIC_IT_USER;
  constant GIC_UART                   : natural  := PICOSOC_USER_GIC_UART   ;
  constant GIC_TIMER                  : natural  := PICOSOC_USER_GIC_TIMER  ;

  constant GIC_WIDTH                  : positive := 3;

  constant GIC_ITS_SYNC_ENABLE        : std_logic_vector(GIC_WIDTH-1 downto 0) := (GIC_IT_USER => '0',
                                                                                   others      => '0');

  -- Timer
  signal   timer_disable              : std_logic;
  signal   timer_clear                : std_logic;
  signal   timer_it                   : std_logic;
  
  -- Signals Safety
begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Clock & Reset
  -----------------------------------------------------------------------------
  clk    <= clk_i;
  arst_b <= arst_b_i;
  
  -----------------------------------------------------------------------------
  -- CPU with Safety Logic
  -----------------------------------------------------------------------------
  gen_cpu_cluster : for i in 0 to NB_CPU-1
   
  generate
    -- Signals CPU (post lockstep / TMR)
  signal   cpu_ics                    : std_logic;
  signal   cpu_iaddr                  : std_logic_vector(CPU_IMEM_ADDR_WIDTH-1 downto 0);
  signal   cpu_idata                  : std_logic_vector(CPU_IMEM_DATA_WIDTH-1 downto 0);

  signal   cpu_sbi_ini                : sbi_ini_t(addr (CPU_DMEM_ADDR_WIDTH-1 downto 0),
                                                  wdata(CPU_DMEM_DATA_WIDTH-1 downto 0));
  signal   cpu_sbi_tgt                : sbi_tgt_t(rdata(CPU_DMEM_DATA_WIDTH-1 downto 0));
  signal   cpu_it_val                 : std_logic;
  signal   cpu_it_ack                 : std_logic;

  -- Signals ICN1 - CPU
  signal   icn1_sbi_inim              : sbi_inis_t(ICN1_NB_MASTER-1 downto 0)(addr (CPU_DMEM_ADDR_WIDTH-1 downto 0),
                                                                              wdata(CPU_DMEM_DATA_WIDTH-1 downto 0));
  signal   icn1_sbi_tgtm              : sbi_tgts_t(ICN1_NB_MASTER-1 downto 0)(rdata(CPU_DMEM_DATA_WIDTH-1 downto 0));

  signal   icn1_sbi_inis              : sbi_inis_t(ICN1_NB_TARGET-1 downto 0)(addr (CPU_DMEM_ADDR_WIDTH-1 downto 0),
                                                                              wdata(CPU_DMEM_DATA_WIDTH-1 downto 0));
  signal   icn1_sbi_tgts              : sbi_tgts_t(ICN1_NB_TARGET-1 downto 0)(rdata(CPU_DMEM_DATA_WIDTH-1 downto 0));

  -- Interruption Vector
  signal   gic_it_vector              : std_logic_vector(GIC_WIDTH-1 downto 0);

  begin

    gen_cpu0_debug :
    if i = 0 
    generate
      debug_o.cpu_iaddr   <= cpu_iaddr                        ;
      debug_o.cpu_idata   <= cpu_idata                        ;
      debug_o.cpu_dcs     <= cpu_sbi_ini.cs                   ;
      debug_o.cpu_dre     <= cpu_sbi_ini.re                   ;
      debug_o.cpu_dwe     <= cpu_sbi_ini.we                   ;
      debug_o.cpu_daddr   <= cpu_sbi_ini.addr                 ;
      debug_o.cpu_dready  <= cpu_sbi_tgt.ready                ;
    end generate;

    ins_cpu_safety : cpu_safety
      generic map
      (SAFETY               => SAFETY
      ,LOCK_STEP_DEPTH      => LOCK_STEP_DEPTH
      ,FAULT_INJECTION      => FAULT_INJECTION
      ,CPU_MODEL            => CPU_MODEL
      ,HARTID               => std_logic_vector(to_unsigned(i, 32))
      ,IMEM_ADDR_WIDTH      => CPU_IMEM_ADDR_WIDTH
      ,IMEM_DATA_WIDTH      => CPU_IMEM_DATA_WIDTH
      ,DMEM_ADDR_WIDTH      => CPU_DMEM_ADDR_WIDTH
      ,DMEM_DATA_WIDTH      => CPU_DMEM_DATA_WIDTH
       )
      port map
      (clk_i                => clk         
      ,cke_i                => '1'         
      ,arst_b_i             => arst_b
      ,ics_o                => cpu_ics
      ,iaddr_o              => cpu_iaddr
      ,idata_i              => cpu_idata
      ,sbi_ini_o            => cpu_sbi_ini
      ,sbi_tgt_i            => cpu_sbi_tgt
      ,interrupt_i          => cpu_it_val
      ,interrupt_ack_o      => cpu_it_ack
      ,inject_error_i       => inject_error_i
      ,diff_o               => diff_o
      );

    icn1_sbi_inim(0)    <= cpu_sbi_ini;
    cpu_sbi_tgt         <= icn1_sbi_tgtm(0);

    -----------------------------------------------------------------------------
    -- CPU ROM
    -----------------------------------------------------------------------------
    ins_ROM_user : entity asylum.ROM_user(rom)
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
    ins_sbi_icn1 : sbi_icn
      generic map
      (NAME                   => "ICN1_user"
      ,NB_MASTER              => ICN1_NB_MASTER
      ,MASTER_SEL             => ICN_MASTER_SEL
      ,NB_TARGET              => ICN1_NB_TARGET
      ,TARGET_SEL             => ICN_TARGET_SEL
      ,TARGET_ID              => ICN1_TARGET_ID
      ,TARGET_ADDR_WIDTH      => ICN1_TARGET_ADDR_WIDTH
      ,TARGET_ADDR_ENCODING   => ICN1_TARGET_ADDR_ENCODING
      ,INTERNAL_DEFAULT_SLAVE => false
        )
      port map
      (clk_i                  => clk      
      ,cke_i                  => '1'         
      ,arst_b_i               => arst_b      
      ,sbi_inis_i             => icn1_sbi_inim
      ,sbi_tgts_o             => icn1_sbi_tgtm
      ,sbi_inis_o             => icn1_sbi_inis
      ,sbi_tgts_i             => icn1_sbi_tgts
      );

    icn2_sbi_inim(i)                <= icn1_sbi_inis(ICN1_TARGET_ICN2);
    icn1_sbi_tgts(ICN1_TARGET_ICN2) <= icn2_sbi_tgtm(i);

    -----------------------------------------------------------------------------
    -- GIC - Interruption Vector
    -----------------------------------------------------------------------------
    -- Same interruptions for all CPUs
    gic_it_vector(GIC_IT_USER) <= it_i   ;
    gic_it_vector(GIC_UART   ) <= uart_it;
    gic_it_vector(GIC_TIMER  ) <= timer_it;
  
    ins_sbi_gic : sbi_GIC
      generic map
      (ITS_SYNC_ENABLE      => GIC_ITS_SYNC_ENABLE
       )
      port map
      (clk_i                => clk         
      ,arst_b_i             => arst_b      
      ,sbi_ini_i            => icn1_sbi_inis(ICN1_TARGET_GIC)
      ,sbi_tgt_o            => icn1_sbi_tgts(ICN1_TARGET_GIC)
      ,its_i                => gic_it_vector
      ,itm_o                => cpu_it_val
      );
  
    -----------------------------------------------------------------------------
    -- RAM1
    -----------------------------------------------------------------------------
    ins_sbi_ram1 : sbi_ram
      generic map
      (DEPTH                => RAM1_DEPTH
      ,SYNC_READ            => true   
     )
      port map
      (clk_i                => clk         
      ,arst_b_i             => arst_b      
      ,sbi_ini_i            => icn1_sbi_inis(ICN1_TARGET_RAM1)
      ,sbi_tgt_o            => icn1_sbi_tgts(ICN1_TARGET_RAM1)
      );
  
  end generate;

  -----------------------------------------------------------------------------
  -- Interconnect
  -- From 1 Initiator to N Target
  -----------------------------------------------------------------------------
  ins_sbi_icn2 : sbi_icn
    generic map
    (NAME                   => "ICN2_user"
    ,NB_MASTER              => ICN2_NB_MASTER
    ,MASTER_SEL             => ICN_MASTER_SEL
    ,NB_TARGET              => ICN2_NB_TARGET
    ,TARGET_SEL             => ICN_TARGET_SEL
    ,TARGET_ID              => ICN2_TARGET_ID
    ,TARGET_ADDR_WIDTH      => ICN2_TARGET_ADDR_WIDTH
    ,TARGET_ADDR_ENCODING   => ICN2_TARGET_ADDR_ENCODING
    ,INTERNAL_DEFAULT_SLAVE => true
      )
    port map
    (clk_i                  => clk      
    ,cke_i                  => '1'         
    ,arst_b_i               => arst_b      
    ,sbi_inis_i             => icn2_sbi_inim
    ,sbi_tgts_o             => icn2_sbi_tgtm
    ,sbi_inis_o             => icn2_sbi_inis
    ,sbi_tgts_i             => icn2_sbi_tgts
    );

  -----------------------------------------------------------------------------
  -- GPIO 0 - Switch
  -----------------------------------------------------------------------------
  ins_sbi_switch : sbi_GPIO
    generic map
    (NAME                 => "SWITCH"
    ,NB_IO                => NB_SWITCH
    ,DATA_OE_INIT         => CST0(8-1 downto 0)
    ,IT_ENABLE            => false
    )
    port map
    (clk_i                => clk           
    ,cke_i                => '1'           
    ,arstn_i              => arst_b         
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_SWITCH)   
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_SWITCH)   
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
    (NAME                 => "LED0"
    ,NB_IO                => NB_LED0
    ,DATA_OE_INIT         => CST1(8-1 downto 0)
    ,IT_ENABLE            => false
    )
    port map
    (clk_i                => clk         
    ,cke_i                => '1'         
    ,arstn_i              => arst_b       
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_LED0) 
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_LED0) 
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
    (NAME                 => "LED1"
    ,NB_IO                => NB_LED1 
    ,DATA_OE_INIT         => CST1(8-1 downto 0)
    ,IT_ENABLE            => false
    )
    port map
    (clk_i                => clk         
    ,cke_i                => '1'         
    ,arstn_i              => arst_b       
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_LED1) 
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_LED1) 
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
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_UART)   
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_UART)   
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
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_SPI)   
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_SPI)   
    ,sclk_o               => spi_sclk_o   
    ,sclk_oe_o            => open
    ,cs_b_o               => spi_cs_b_o   
    ,cs_b_oe_o            => open
    ,mosi_o               => spi_mosi_o   
    ,mosi_oe_o            => open
    ,miso_i               => spi_miso_i   
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
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_TIMER)
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_TIMER)
    ,timer_disable_i      => timer_disable
    ,timer_clear_i        => timer_clear
    ,it_o                 => timer_it
    );
  
  -----------------------------------------------------------------------------
  -- CRC
  -----------------------------------------------------------------------------
  ins_sbi_crc : sbi_crc
    generic map
    (NAME             => "CRC16"
    ,WIDTH_CRC        => 16     
    ,WIDTH_DATA       => 8      
    ,POLYNOM          => X"A001"
    ,SHIFT_LEFT       => false  
    ,LSB_FIRST        => true   
    ,POLYNOM_REVERSE  => false  
    ,REFLECT_IN       => false  
    ,REFLECT_OUT      => false  
    ,XOR_OUT          => (others => '0')
      )
    port map
    (clk_i                => clk         
    ,arst_b_i             => arst_b      
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_CRC)
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_CRC)
    );

  -----------------------------------------------------------------------------
  -- spinlock
  -----------------------------------------------------------------------------
  ins_sbi_spinlock : sbi_spinlock
    port map
    (clk_i                => clk         
    ,arst_b_i             => arst_b      
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_SPINLOCK)
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_SPINLOCK)
    );

  -----------------------------------------------------------------------------
  -- mailbox
  -----------------------------------------------------------------------------
  ins_sbi_mailbox : sbi_mailbox
    generic map
     (FIFO0_DEPTH_TX       => MAILBOX_FIFO0_DEPTH_TX
     ,FIFO0_DEPTH_RX       => MAILBOX_FIFO0_DEPTH_RX
     ,FIFO1_DEPTH_TX       => MAILBOX_FIFO1_DEPTH_TX
     ,FIFO1_DEPTH_RX       => MAILBOX_FIFO1_DEPTH_RX
      )
    port map
     (clk_i                => clk         
     ,arst_b_i             => arst_b      
     ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_MAILBOX)
     ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_MAILBOX)
      );

  -----------------------------------------------------------------------------
  -- RAM2
  -----------------------------------------------------------------------------
  ins_sbi_ram2 : sbi_ram
    generic map
    (DEPTH                => RAM2_DEPTH
    ,SYNC_READ            => true   
   )
    port map
    (clk_i                => clk         
    ,arst_b_i             => arst_b      
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_RAM2)
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_RAM2)
    );
    
  -----------------------------------------------------------------------------
  -- Debug
  -----------------------------------------------------------------------------
  debug_o.arst_b      <= arst_b                           ;
  debug_o.switch_cs   <= icn2_sbi_inis(ICN2_TARGET_SWITCH).cs   ;
  debug_o.switch_ready<= icn2_sbi_tgts(ICN2_TARGET_SWITCH).ready;
  debug_o.led0_cs     <= icn2_sbi_inis(ICN2_TARGET_LED0  ).cs   ;
  debug_o.led0_ready  <= icn2_sbi_tgts(ICN2_TARGET_LED0  ).ready;
  debug_o.led1_cs     <= icn2_sbi_inis(ICN2_TARGET_LED1  ).cs   ;
  debug_o.led1_ready  <= icn2_sbi_tgts(ICN2_TARGET_LED1  ).ready;
  debug_o.uart_cs     <= icn2_sbi_inis(ICN2_TARGET_UART  ).cs   ;
  debug_o.uart_ready  <= icn2_sbi_tgts(ICN2_TARGET_UART  ).ready;
  debug_o.spi_cs      <= icn2_sbi_inis(ICN2_TARGET_SPI   ).cs   ;
  debug_o.spi_ready   <= icn2_sbi_tgts(ICN2_TARGET_SPI   ).ready;
    
end architecture rtl;
    
