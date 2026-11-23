-------------------------------------------------------------------------------
-- Title      : PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : PicoSoC.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2026-07-20
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
-- 2026-08-01  3.9      mrosiere Use GPIO_irq instead of GPIO
-- 2026-10-05  3.10     mrosiere diff_o : OR of the diff of all CPU clusters
-- 2026-11-19  3.11     mrosiere LED GPIO data_i sized with NB_LED0 / NB_LED1
--                               (was driven by every cluster when NB_CPU > 1)
-- 2026-11-16  3.11     mrosiere Mailbox : "data available" in fifo0 / fifo1
--                               (not fifo_empty_o) as user GIC sources 3 / 4
-- 2026-11-21  3.12     mrosiere Switch edges as user GIC source 5
-- 2026-11-21  3.13     mrosiere Add I2C (master and slave)
-- 2026-11-21  3.14     mrosiere Add PWM
-- 2026-11-21  3.15     mrosiere Debug record : data of the CPU0 bus
-- 2026-11-23  3.16     mrosiere CPU_DEBUG_ENABLE : debug unit of the CPU of
--                               every cluster, JTAG chain of the clusters
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
use     asylum.GPIO_irq_csr_pkg.all;
use     asylum.UART_csr_pkg.all;
use     asylum.SPI_csr_pkg.all;
use     asylum.GIC_csr_pkg.all;
use     asylum.timer_csr_pkg.all;
use     asylum.crc_csr_pkg.all;
use     asylum.spinlock_csr_pkg.all;
use     asylum.mailbox_csr_pkg.all;
use     asylum.I2C_csr_pkg.all;
use     asylum.PWM_csr_pkg.all;
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
use     asylum.i2c_pkg.all;
use     asylum.pwm_pkg.all;
use     asylum.icn_pkg.all;
use     asylum.ram_pkg.all;
use     asylum.ROM_user_pkg.all;
use     asylum.jtag_pkg.all;

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
    ;CPU_DEBUG_ENABLE       : boolean  := False -- Debug unit of the CPU of every cluster (WardRV_fsm)
    ;IDCODE_VALUE           : std_logic_vector(31 downto 0) := x"10000001" -- IDCODE of the TAP of cluster 0, + i * 0x10000 for cluster i
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
    ;spi_sclk_oe_o         : out std_logic
    ;spi_cs_b_o            : out std_logic
    ;spi_cs_b_oe_o         : out std_logic
    ;spi_io_o              : out std_logic_vector(        8-1 downto 0)
    ;spi_io_i              : in  std_logic_vector(        8-1 downto 0)
    ;spi_io_oe_o           : out std_logic_vector(        8-1 downto 0)

    -- I2C Interface (open drain : xx_o is 0, xx_oe_o = 1 pulls the line low)
    ;i2c_scl_i             : in  std_logic
    ;i2c_scl_o             : out std_logic
    ;i2c_scl_oe_o          : out std_logic
    ;i2c_sda_i             : in  std_logic
    ;i2c_sda_o             : out std_logic
    ;i2c_sda_oe_o          : out std_logic

    -- PWM Interface
    ;pwm_o                 : out std_logic
                          
    ;it_i                  : in  std_logic
    ;inject_error_i        : in  std_logic_vector(        3-1 downto 0)
    ;diff_o                : out std_logic_vector(        3-1 downto 0) -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0
                                 
    ;debug_o               : out PicoSoC_user_debug_t

    -- CPU debug (CPU_DEBUG_ENABLE) : JTAG chain of the clusters (TDI ->
    -- cluster 0 -> ... -> TDO), power-on reset of the debug units, ndmreset
    ;dbg_arst_b_i          : in  std_logic := '1'
    ;jtag_ini_i            : in  jtag_ini_t
    ;jtag_tgt_o            : out jtag_tgt_t
    ;ndmreset_o            : out std_logic
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
     ,ICN1_TARGET_ICN2                => CPU_DMEM_ADDR_WIDTH
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
  constant ICN2_TARGET_I2C            : integer  := 10;
  constant ICN2_TARGET_PWM            : integer  := 11;
  
  constant ICN2_NB_TARGET             : positive := 12;
  
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
     ,ICN2_TARGET_I2C                 => PICOSOC_USER_I2C_BA
     ,ICN2_TARGET_PWM                 => PICOSOC_USER_PWM_BA
      );

  constant ICN2_TARGET_ADDR_WIDTH     : naturals_t    (ICN2_NB_TARGET-1 downto 0) :=
    ( ICN2_TARGET_SWITCH              => GPIO_IRQ_ADDR_WIDTH
     ,ICN2_TARGET_LED0                => GPIO_IRQ_ADDR_WIDTH
     ,ICN2_TARGET_LED1                => GPIO_IRQ_ADDR_WIDTH
     ,ICN2_TARGET_UART                => UART_ADDR_WIDTH
     ,ICN2_TARGET_SPI                 => SPI_ADDR_WIDTH
     ,ICN2_TARGET_TIMER               => TIMER_ADDR_WIDTH
     ,ICN2_TARGET_CRC                 => CRC_ADDR_WIDTH
     ,ICN2_TARGET_SPINLOCK            => SPINLOCK_ADDR_WIDTH
     ,ICN2_TARGET_MAILBOX             => MAILBOX_ADDR_WIDTH
     ,ICN2_TARGET_RAM2                => log2(RAM2_DEPTH)
     ,ICN2_TARGET_I2C                 => I2C_ADDR_WIDTH
     ,ICN2_TARGET_PWM                 => PWM_ADDR_WIDTH
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
  signal   switch_it                  : std_logic;
  
  -- Interruption Vector
  constant GIC_IT_USER                : natural  := PICOSOC_USER_GIC_IT_USER ;
  constant GIC_UART                   : natural  := PICOSOC_USER_GIC_UART    ;
  constant GIC_TIMER                  : natural  := PICOSOC_USER_GIC_TIMER   ;
  constant GIC_MAILBOX0               : natural  := PICOSOC_USER_GIC_MAILBOX0;
  constant GIC_MAILBOX1               : natural  := PICOSOC_USER_GIC_MAILBOX1;
  constant GIC_SWITCH                 : natural  := PICOSOC_USER_GIC_SWITCH  ;

  constant GIC_WIDTH                  : positive := 6;

  -- it_i comes from a pad (push button), asynchronous to clk_i : resynchronize it in the GIC
  -- UART, Timer, Mailbox and Switch interruptions are already synchronous
  constant GIC_ITS_SYNC_ENABLE        : std_logic_vector(GIC_WIDTH-1 downto 0) := (GIC_IT_USER => '1',
                                                                                   others      => '0');

  -- Timer
  signal   timer_disable              : std_logic;
  signal   timer_clear                : std_logic;
  signal   timer_it                   : std_logic;

  -- I2C : SCL at 100 kHz after reset, a quarter of the SCL period is
  -- (prescaler+1) cycles of clk
  constant I2C_PRESCALER_RATIO        : std_logic_vector(8-1 downto 0) := std_logic_vector(to_unsigned(CLOCK_FREQ/400_000-1, 8));

  -- Mailbox
  signal   mailbox_empty              : std_logic_vector(2-1 downto 0);
  signal   mailbox_it                 : std_logic_vector(2-1 downto 0);
  
  -- Signals Safety
  type     diff_vector_t              is array (natural range <>) of std_logic_vector(3-1 downto 0);
  signal   cpu_diff                   : diff_vector_t(NB_CPU-1 downto 0); -- diff of each CPU cluster

  -- JTAG chain of the clusters : jtag_chain(i) = TDO before cluster i, with
  -- the OR of the TDO enables (a CPU without debug unit is a wire, never
  -- drives TDO)
  type     jtag_tgts_t                is array (natural range <>) of jtag_tgt_t;
  signal   jtag_chain                 : jtag_tgts_t(0 to NB_CPU);
  signal   cpu_ndmreset               : std_logic_vector(NB_CPU-1 downto 0);
begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Clock & Reset
  -----------------------------------------------------------------------------
  clk    <= clk_i;
  arst_b <= arst_b_i;
  
  -----------------------------------------------------------------------------
  -- Safety difference : OR of all CPU clusters
  -----------------------------------------------------------------------------
  p_diff : process (cpu_diff) is
    variable v_diff : std_logic_vector(3-1 downto 0);
  begin  -- process p_diff
    v_diff := (others => '0');
    for i in cpu_diff'range loop
      v_diff := v_diff or cpu_diff(i);
    end loop;
    diff_o <= v_diff;
  end process p_diff;

  -----------------------------------------------------------------------------
  -- JTAG chain of the clusters, ndmreset of any debug unit
  -----------------------------------------------------------------------------
  jtag_chain(0) <= (tdo => jtag_ini_i.tdi, tdo_en => '0');
  jtag_tgt_o    <= jtag_chain(NB_CPU);
  ndmreset_o    <= reduce_or(cpu_ndmreset);

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

  -- JTAG of the cluster
  signal   cpu_jtag_ini               : jtag_ini_t;
  signal   cpu_jtag_tgt               : jtag_tgt_t;

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
      debug_o.cpu_dwdata  <= cpu_sbi_ini.wdata                ;
      debug_o.cpu_drdata  <= cpu_sbi_tgt.rdata                ;
      debug_o.cpu_dready  <= cpu_sbi_tgt.ready                ;
    end generate;

    ins_cpu_safety : cpu_safety
      generic map
      (SAFETY               => SAFETY
      ,LOCK_STEP_DEPTH      => LOCK_STEP_DEPTH
      ,FAULT_INJECTION      => FAULT_INJECTION
      ,CPU_MODEL            => CPU_MODEL
      ,HARTID               => std_logic_vector(to_unsigned(i, 32))
      ,DEBUG_ENABLE         => CPU_DEBUG_ENABLE
      ,IDCODE_VALUE         => std_logic_vector(unsigned(IDCODE_VALUE) + to_unsigned(i * 16#10000#, 32))
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
      ,diff_o               => cpu_diff(i)
      ,dbg_arst_b_i         => dbg_arst_b_i
      ,jtag_ini_i           => cpu_jtag_ini
      ,jtag_tgt_o           => cpu_jtag_tgt
      ,ndmreset_o           => cpu_ndmreset(i)
      );

    -- JTAG chain : TDI from the previous cluster
    cpu_jtag_ini      <= (tck => jtag_ini_i.tck, trst_n => jtag_ini_i.trst_n, tms => jtag_ini_i.tms, tdi => jtag_chain(i).tdo);
    jtag_chain(i+1)   <= (tdo => cpu_jtag_tgt.tdo, tdo_en => cpu_jtag_tgt.tdo_en or jtag_chain(i).tdo_en);

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
    gic_it_vector(GIC_IT_USER ) <= it_i         ;
    gic_it_vector(GIC_UART    ) <= uart_it      ;
    gic_it_vector(GIC_TIMER   ) <= timer_it     ;
    gic_it_vector(GIC_MAILBOX0) <= mailbox_it(0);
    gic_it_vector(GIC_MAILBOX1) <= mailbox_it(1);
    gic_it_vector(GIC_SWITCH  ) <= switch_it    ;
  
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
  ins_sbi_switch : sbi_GPIO_irq
    generic map
    (NAME                 => "SWITCH"
    ,NB_IO                => NB_SWITCH
    ,DATA_OE_INIT         => CST0(8-1 downto 0)
    ,IRQ_POSEDGE          => X"FF"
    ,IRQ_NEGEDGE          => X"FF"
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
    ,it_o                 => switch_it
    );

  -----------------------------------------------------------------------------
  -- GPIO 1 - LED
  -----------------------------------------------------------------------------
  ins_sbi_led0 : sbi_GPIO_irq
    generic map
    (NAME                 => "LED0"
    ,NB_IO                => NB_LED0
    ,DATA_OE_INIT         => CST1(8-1 downto 0)
    ,IRQ_POSEDGE          => X"00"
    ,IRQ_NEGEDGE          => X"00"
    )
    port map
    (clk_i                => clk         
    ,cke_i                => '1'         
    ,arstn_i              => arst_b       
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_LED0) 
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_LED0) 
    ,data_i               => CST0(NB_LED0-1 downto 0)
    ,data_o               => led0_o      
    ,data_oe_o            => open        
    ,it_o                 => open       
    );

  -----------------------------------------------------------------------------
  -- GPIO 2 - LED
  -----------------------------------------------------------------------------
  ins_sbi_led1 : sbi_GPIO_irq
    generic map
    (NAME                 => "LED1"
    ,NB_IO                => NB_LED1 
    ,DATA_OE_INIT         => CST1(8-1 downto 0)
    ,IRQ_POSEDGE          => X"00"
    ,IRQ_NEGEDGE          => X"00"
    )
    port map
    (clk_i                => clk         
    ,cke_i                => '1'         
    ,arstn_i              => arst_b       
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_LED1) 
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_LED1) 
    ,data_i               => CST0(NB_LED1-1 downto 0)
    ,data_o               => led1_o      
    ,data_oe_o            => open        
    ,it_o                 => open       
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
    ,HANDLE_HOLD_WP       => true
     )
    port map
    (clk_i                => clk           
    ,arst_b_i             => arst_b        
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_SPI)   
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_SPI)   
    ,sclk_o               => spi_sclk_o   
    ,sclk_oe_o            => spi_sclk_oe_o
    ,cs_b_o               => spi_cs_b_o   
    ,cs_b_oe_o            => spi_cs_b_oe_o
    ,io_o                 => spi_io_o
    ,io_i                 => spi_io_i
    ,io_oe_o              => spi_io_oe_o
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
  -- Interruption of fifo<n> : data available (level, synchronous to clk)
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
     ,fifo_empty_o         => mailbox_empty
     ,fifo_full_o          => open
      );

  mailbox_it <= not mailbox_empty;

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
  -- I2C
  -- Master and slave (slave address in cfg), prescaler writable by software
  -----------------------------------------------------------------------------
  ins_sbi_i2c : sbi_I2C
    generic map
    (NAME                 => "I2C"
    ,USER_DEFINE_PRESCALER=> true
    ,PRESCALER_RATIO      => I2C_PRESCALER_RATIO
    ,MASTER_ENABLE        => true
    ,SLAVE_ENABLE         => true
     )
    port map
    (clk_i                => clk         
    ,arst_b_i             => arst_b      
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_I2C)
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_I2C)
    ,scl_i                => i2c_scl_i
    ,scl_o                => i2c_scl_o
    ,scl_oe_o             => i2c_scl_oe_o
    ,sda_i                => i2c_sda_i
    ,sda_o                => i2c_sda_o
    ,sda_oe_o             => i2c_sda_oe_o
     );

  -----------------------------------------------------------------------------
  -- PWM
  -- One output, prescaler writable by software
  -----------------------------------------------------------------------------
  ins_sbi_pwm : sbi_PWM
    generic map
    (NAME                 => "PWM"
     )
    port map
    (clk_i                => clk         
    ,arst_b_i             => arst_b      
    ,sbi_ini_i            => icn2_sbi_inis(ICN2_TARGET_PWM)
    ,sbi_tgt_o            => icn2_sbi_tgts(ICN2_TARGET_PWM)
    ,pwm_o                => pwm_o
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
    
