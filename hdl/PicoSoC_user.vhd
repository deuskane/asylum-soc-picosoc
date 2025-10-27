-------------------------------------------------------------------------------
-- Title      : PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : PicoSoC.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2025-10-25
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
-------------------------------------------------------------------------------


library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.pbi_pkg.all;
use     asylum.GPIO_csr_pkg.all;
use     asylum.UART_csr_pkg.all;
use     asylum.SPI_csr_pkg.all;
use     asylum.GIC_csr_pkg.all;
use     asylum.PicoSoC_pkg.all;
use     asylum.pbi_OpenBlaze8_pkg.all;
use     asylum.gpio_pkg.all;
use     asylum.uart_pkg.all;
use     asylum.spi_pkg.all;
use     asylum.gic_pkg.all;
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
    ;SAFETY                : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;FAULT_INJECTION       : boolean  := False
    
    ;ICN_ALGO_SEL          : string := "or"
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
  constant CPU1_ENABLE                : boolean := ((SAFETY = "lock-step") or
                                                    (SAFETY = "tmr"));
  constant CPU2_ENABLE                : boolean := ((SAFETY = "tmr"));

  -- ICN Configuration
  constant TARGET_ADDR_ENCODING       : string := "binary";
  
  constant NB_TARGET                  : positive := 6;

  constant TARGET_SWITCH              : integer  := 0;
  constant TARGET_LED0                : integer  := 1;
  constant TARGET_LED1                : integer  := 2;
  constant TARGET_UART                : integer  := 3;
  constant TARGET_SPI                 : integer  := 4;
  constant TARGET_GIC                 : integer  := 5;
  
  constant TARGET_ID                  : pbi_addrs_t   (NB_TARGET-1 downto 0) :=
    ( TARGET_SWITCH                   => X"10"
     ,TARGET_LED0                     => X"20"
     ,TARGET_LED1                     => X"40"
     ,TARGET_UART                     => X"80"
     ,TARGET_SPI                      => X"08"
     ,TARGET_GIC                      => X"F0"
      );

  constant TARGET_ADDR_WIDTH          : naturals_t    (NB_TARGET-1 downto 0) :=
    ( TARGET_SWITCH                   => GPIO_ADDR_WIDTH
     ,TARGET_LED0                     => GPIO_ADDR_WIDTH
     ,TARGET_LED1                     => GPIO_ADDR_WIDTH
     ,TARGET_UART                     => UART_ADDR_WIDTH
     ,TARGET_SPI                      => SPI_ADDR_WIDTH
     ,TARGET_GIC                      => GIC_ADDR_WIDTH
      );
  
  -- Signals ICN
  signal   icn_pbi_inis               : pbi_inis_t(NB_TARGET-1 downto 0)(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                                         wdata(PBI_DATA_WIDTH-1 downto 0));
  signal   icn_pbi_tgts               : pbi_tgts_t(NB_TARGET-1 downto 0)(rdata(PBI_DATA_WIDTH-1 downto 0));

  -- Signals Clock/Reset
  signal   clk                        : std_logic;
  signal   arst_b                     : std_logic;

  -- Signals CPUs
  signal   cpu0_ics                   : std_logic;
  signal   cpu0_iaddr                 : std_logic_vector(10-1 downto 0);
  signal   cpu0_idata                 : std_logic_vector(18-1 downto 0);
  signal   cpu0_pbi_ini               : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal   cpu0_it_ack                : std_logic;
  
  signal   cpu1_ics                   : std_logic;
  signal   cpu1_iaddr                 : std_logic_vector(10-1 downto 0);
  signal   cpu1_idata                 : std_logic_vector(18-1 downto 0);
  signal   cpu1_pbi_ini               : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal   cpu1_it_ack                : std_logic;
  
  signal   cpu2_ics                   : std_logic;
  signal   cpu2_iaddr                 : std_logic_vector(10-1 downto 0);
  signal   cpu2_idata                 : std_logic_vector(18-1 downto 0);
  signal   cpu2_pbi_ini               : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal   cpu2_it_ack                : std_logic;

  -- Signals CPU (post lockstep / TMR)
  signal   cpu_ics                    : std_logic;
  signal   cpu_iaddr                  : std_logic_vector(10-1 downto 0);
  signal   cpu_idata                  : std_logic_vector(18-1 downto 0);

  signal   cpu_pbi_ini                : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal   cpu_pbi_tgt                : pbi_tgt_t(rdata(PBI_DATA_WIDTH-1 downto 0));
  signal   cpu_it_val                 : std_logic;
  signal   cpu_it_ack                 : std_logic;

  -- UART
  signal   uart_it                    : std_logic;
  
  -- Interruption Vector
  constant GIC_WIDTH                  : positive := 2;

  constant GIC_IT_USER                : natural  := 0;
  constant GIC_UART                   : natural  := 1;

  signal   gic_it_vector              : std_logic_vector(GIC_WIDTH-1 downto 0);
  
  -- Signals Safety
  signal   diff                       : std_logic_vector(3-1 downto 0); -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0
  signal   diff_r                     : std_logic_vector(3-1 downto 0); -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0

begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Clock & Reset
  -----------------------------------------------------------------------------
  clk    <= clk_i;
  arst_b <= arst_b_i;
  
  -----------------------------------------------------------------------------
  -- CPU 0
  -----------------------------------------------------------------------------
  ins_pbi_OpenBlaze8_0 : pbi_OpenBlaze8
    generic map
    (RAM_DEPTH            => 256
     )
    port map
    (clk_i                => clk         
    ,cke_i                => '1'         
    ,arstn_i              => arst_b      
    ,ics_o                => cpu0_ics    
    ,iaddr_o              => cpu0_iaddr  
    ,idata_i              => cpu0_idata  
    ,pbi_ini_o            => cpu0_pbi_ini
    ,pbi_tgt_i            => cpu_pbi_tgt 
    ,interrupt_i          => cpu_it_val  
    ,interrupt_ack_o      => cpu0_it_ack
    );

  -----------------------------------------------------------------------------
  -- CPU ROM
  -----------------------------------------------------------------------------
  ins_pbi_OpenBlaze8_ROM : entity asylum.ROM_user(rom)
    port map
    (clk_i                => clk      
    ,cke_i                => cpu_ics  
    ,address_i            => cpu_iaddr
    ,instruction_o        => cpu_idata
    );

  -----------------------------------------------------------------------------
  -- CPU Signals
  --  * ROM interface
  --  * ICN interface
  --  * IT  interface
  --
  -- If safety none or lock-step : take cpu 0
  -- else if tmr : vote all cpu output
  -----------------------------------------------------------------------------
  gen_cpu_vote: if SAFETY = "tmr"
  generate
    cpu_ics        <= ((cpu0_ics     and cpu1_ics    ) or
                       (cpu1_ics     and cpu2_ics    ) or
                       (cpu2_ics     and cpu0_ics    ));
    cpu_iaddr      <= ((cpu0_iaddr   and cpu1_iaddr  ) or
                       (cpu1_iaddr   and cpu2_iaddr  ) or
                       (cpu2_iaddr   and cpu0_iaddr  ));
    cpu_pbi_ini    <= ((cpu0_pbi_ini and cpu1_pbi_ini) or
                       (cpu1_pbi_ini and cpu2_pbi_ini) or
                       (cpu2_pbi_ini and cpu0_pbi_ini));
    cpu_it_ack     <= ((cpu0_it_ack  and cpu1_it_ack ) or
                       (cpu1_it_ack  and cpu2_it_ack ) or
                       (cpu2_it_ack  and cpu0_it_ack ));
  end generate;

  gen_cpu_vote_b: if SAFETY /= "tmr"
  generate
    cpu_ics        <= cpu0_ics     ;
    cpu_iaddr      <= cpu0_iaddr   ;
    cpu_pbi_ini    <= cpu0_pbi_ini ;
    cpu_it_ack     <= cpu0_it_ack  ;
  end generate;
  
  -----------------------------------------------------------------------------
  -- Interconnect
  -- From 1 Initiator to N Target
  -----------------------------------------------------------------------------
  ins_pbi_icn : pbi_icn
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
    ,pbi_ini_i            => cpu_pbi_ini 
    ,pbi_tgt_o            => cpu_pbi_tgt 
    ,pbi_inis_o           => icn_pbi_inis
    ,pbi_tgts_i           => icn_pbi_tgts
    );

  -----------------------------------------------------------------------------
  -- GPIO 0 - Switch
  -----------------------------------------------------------------------------
  ins_pbi_switch : pbi_GPIO
    generic map
    (NB_IO                => NB_SWITCH
    ,DATA_OE_INIT         => CST0(8-1 downto 0)
    ,IT_ENABLE            => false
    )
    port map
    (clk_i                => clk           
    ,cke_i                => '1'           
    ,arstn_i              => arst_b         
    ,pbi_ini_i            => icn_pbi_inis(TARGET_SWITCH)   
    ,pbi_tgt_o            => icn_pbi_tgts(TARGET_SWITCH)   
    ,data_i               => switch_i      
    ,data_o               => open          
    ,data_oe_o            => open          
    ,interrupt_o          => open          
    ,interrupt_ack_i      => '0'
    );

  -----------------------------------------------------------------------------
  -- GPIO 1 - LED
  -----------------------------------------------------------------------------
  ins_pbi_led0 : pbi_GPIO
    generic map
    (NB_IO                => NB_LED0
    ,DATA_OE_INIT         => CST1(8-1 downto 0)
    ,IT_ENABLE            => false
    )
    port map
    (clk_i                => clk         
    ,cke_i                => '1'         
    ,arstn_i              => arst_b       
    ,pbi_ini_i            => icn_pbi_inis(TARGET_LED0) 
    ,pbi_tgt_o            => icn_pbi_tgts(TARGET_LED0) 
    ,data_i               => X"00"       
    ,data_o               => led0_o      
    ,data_oe_o            => open        
    ,interrupt_o          => open        
    ,interrupt_ack_i      => '0'
    );

  -----------------------------------------------------------------------------
  -- GPIO 2 - LED
  -----------------------------------------------------------------------------
  ins_pbi_led1 : pbi_GPIO
    generic map
    (NB_IO                => NB_LED1
    ,DATA_OE_INIT         => CST1(8-1 downto 0)
    ,IT_ENABLE            => false
    )
    port map
    (clk_i                => clk         
    ,cke_i                => '1'         
    ,arstn_i              => arst_b       
    ,pbi_ini_i            => icn_pbi_inis(TARGET_LED1) 
    ,pbi_tgt_o            => icn_pbi_tgts(TARGET_LED1) 
    ,data_i               => X"00"       
    ,data_o               => led1_o      
    ,data_oe_o            => open        
    ,interrupt_o          => open        
    ,interrupt_ack_i      => '0'
    );

  -----------------------------------------------------------------------------
  -- UART
  -----------------------------------------------------------------------------
  ins_pbi_uart : pbi_uart
    generic map
    (BAUD_RATE            => BAUD_RATE     
    ,CLOCK_FREQ           => CLOCK_FREQ
    ,DEPTH_TX             => UART_DEPTH_TX 
    ,DEPTH_RX             => UART_DEPTH_RX 
     )
    port map
    (clk_i                => clk           
    ,arst_b_i             => arst_b        
    ,pbi_ini_i            => icn_pbi_inis(TARGET_UART)   
    ,pbi_tgt_o            => icn_pbi_tgts(TARGET_UART)   
    ,uart_tx_o            => uart_tx_o     
    ,uart_rx_i            => uart_rx_i
    ,uart_cts_b_i         => uart_cts_b_i
    ,uart_rts_b_o         => uart_rts_b_o
    ,it_o                 => uart_it 
     );

  -----------------------------------------------------------------------------
  -- SPI
  -----------------------------------------------------------------------------
  ins_pbi_spi : pbi_spi
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
    ,pbi_ini_i            => icn_pbi_inis(TARGET_SPI)   
    ,pbi_tgt_o            => icn_pbi_tgts(TARGET_SPI)   
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

  ins_pbi_gic : pbi_GIC
    port map
    (clk_i                => clk         
    ,arst_b_i             => arst_b      
    ,pbi_ini_i            => icn_pbi_inis(TARGET_GIC)
    ,pbi_tgt_o            => icn_pbi_tgts(TARGET_GIC)
    ,its_i                => gic_it_vector
    ,itm_o                => cpu_it_val
    );

-------------------------------------------------------------------------------
---- Interruption
----
---- From level to Val/Ack interruption
-------------------------------------------------------------------------------
--ins_it_ctrl : it_ctrl
--  port map
--  (clk_i                => clk          
--  ,arstn_i              => arst_b   
--  ,it_i                 => it_i         
--  ,it_val_o             => cpu_it_val   
--  ,it_ack_i             => cpu_it_ack
--  );

  
  -----------------------------------------------------------------------------
  -- CPU 1
  -- diff cpu0 vs cpu1
  -----------------------------------------------------------------------------
  gen_cpu1_enable: if CPU1_ENABLE = true
  generate
    -- Lock Step
    ins_pbi_OpenBlaze8_1 : pbi_OpenBlaze8
      generic map
      (RAM_DEPTH            => 256
       )
      port map
      (clk_i                => clk           
      ,cke_i                => '1'     
      ,arstn_i              => arst_b   
      ,ics_o                => cpu1_ics    
      ,iaddr_o              => cpu1_iaddr  
      ,idata_i              => cpu1_idata  
      ,pbi_ini_o            => cpu1_pbi_ini
      ,pbi_tgt_i            => cpu_pbi_tgt 
      ,interrupt_i          => cpu_it_val  
      ,interrupt_ack_o      => cpu1_it_ack
       );

    diff(0) <= '1' when (   (cpu0_ics           /= cpu1_ics          )
                         or (cpu0_iaddr         /= cpu1_iaddr        )
                         or (cpu0_it_ack        /= cpu1_it_ack       )
                       --or (cpu0_pbi_ini       /= cpu1_pbi_ini      )
                            ) else
               '0';
    
    p_diff_r: process (clk, arst_b) is
    begin  -- process p_diff_r
      if arst_b = '0' then                 -- asynchronous reset (active low)
        diff_r(0) <= '0';
      elsif clk'event and clk = '1' then  -- rising clock edge
        -- Trap 1
        diff_r(0) <= diff_r(0) or diff(0);
      end if;
    end process p_diff_r;

    diff_o(0) <= diff_r(0);
  end generate gen_cpu1_enable;
  
  gen_cpu1_disable: if CPU1_ENABLE = false
  generate
    diff_o(0) <= '0';
  end generate gen_cpu1_disable;

  -----------------------------------------------------------------------------
  -- CPU 2
  -- diff cpu1 vs cpu2
  -- diff cpu2 vs cpu0
  -----------------------------------------------------------------------------
  gen_cpu2_enable: if CPU2_ENABLE = true
  generate
    -- TMR
    ins_pbi_OpenBlaze8_2 : pbi_OpenBlaze8
      generic map
      (RAM_DEPTH            => 256
       )
      port map
      (clk_i                => clk           
      ,cke_i                => '1'     
      ,arstn_i              => arst_b   
      ,ics_o                => cpu2_ics    
      ,iaddr_o              => cpu2_iaddr  
      ,idata_i              => cpu2_idata  
      ,pbi_ini_o            => cpu2_pbi_ini
      ,pbi_tgt_i            => cpu_pbi_tgt 
      ,interrupt_i          => cpu_it_val  
      ,interrupt_ack_o      => cpu2_it_ack
       );

    diff(1) <= '1' when (   (cpu1_ics           /= cpu2_ics          )
                         or (cpu1_iaddr         /= cpu2_iaddr        )
                         or (cpu1_it_ack        /= cpu2_it_ack       )
                       --or (cpu1_pbi_ini       /= cpu2_pbi_ini      )
                         ) else
               '0';
    diff(2) <= '1' when (   (cpu2_ics           /= cpu0_ics          )
                         or (cpu2_iaddr         /= cpu0_iaddr        )
                         or (cpu2_it_ack        /= cpu0_it_ack       )
                       --or (cpu2_pbi_ini       /= cpu0_pbi_ini      )
                         ) else
               '0';
    
    p_diff_r: process (clk, arst_b) is
    begin  -- process p_diff_r
      if arst_b = '0' then                 -- asynchronous reset (active low)
        diff_r(2 downto 1) <= "00";
      elsif clk'event and clk = '1' then  -- rising clock edge

        -- Trap 1
        diff_r(2 downto 1) <= diff_r(2 downto 1) or diff(2 downto 1);
      end if;
    end process p_diff_r;

    diff_o(2 downto 1) <= diff_r(2 downto 1);
  end generate gen_cpu2_enable;
  
  gen_cpu2_disable: if CPU2_ENABLE = false
  generate
    diff_o(1) <= '0';
    diff_o(2) <= '0';
  end generate gen_cpu2_disable;

  -----------------------------------------------------------------------------
  -- Fault Injection
  -----------------------------------------------------------------------------
  gen_inject_error:   if FAULT_INJECTION = true
  generate
    cpu0_idata(17)          <= cpu_idata(17) xor inject_error_i(0);
    cpu0_idata(16 downto 0) <= cpu_idata(16 downto 0);

    cpu1_idata(17)          <= cpu_idata(17) xor inject_error_i(1);
    cpu1_idata(16 downto 0) <= cpu_idata(16 downto 0);

    cpu2_idata(17)          <= cpu_idata(17) xor inject_error_i(2);
    cpu2_idata(16 downto 0) <= cpu_idata(16 downto 0);
        
  end generate gen_inject_error;

  gen_inject_error_n: if FAULT_INJECTION = false
  generate
    cpu0_idata              <= cpu_idata;
    cpu1_idata              <= cpu_idata;        
    cpu2_idata              <= cpu_idata;        
  end generate gen_inject_error_n;

  -----------------------------------------------------------------------------
  -- Debug
  -----------------------------------------------------------------------------
  debug_o.arst_b      <= arst_b                          ;
  debug_o.cpu_iaddr   <= cpu_iaddr                       ;
  debug_o.cpu_idata   <= cpu_idata                       ;
  debug_o.cpu_dcs     <= cpu_pbi_ini.cs                  ;
  debug_o.cpu_dre     <= cpu_pbi_ini.re                  ;
  debug_o.cpu_dwe     <= cpu_pbi_ini.we                  ;
  debug_o.cpu_daddr   <= cpu_pbi_ini.addr                ;
  debug_o.cpu_dbusy   <= cpu_pbi_tgt.busy                ;
  debug_o.switch_cs   <= icn_pbi_inis(TARGET_SWITCH).cs  ;
  debug_o.switch_busy <= icn_pbi_tgts(TARGET_SWITCH).busy;
  debug_o.led0_cs     <= icn_pbi_inis(TARGET_LED0  ).cs  ;
  debug_o.led0_busy   <= icn_pbi_tgts(TARGET_LED0  ).busy;
  debug_o.led1_cs     <= icn_pbi_inis(TARGET_LED1  ).cs  ;
  debug_o.led1_busy   <= icn_pbi_tgts(TARGET_LED1  ).busy;
  debug_o.uart_cs     <= icn_pbi_inis(TARGET_UART  ).cs  ;
  debug_o.uart_busy   <= icn_pbi_tgts(TARGET_UART  ).busy;
  debug_o.spi_cs      <= icn_pbi_inis(TARGET_SPI   ).cs  ;
  debug_o.spi_busy    <= icn_pbi_tgts(TARGET_SPI   ).busy;
    
end architecture rtl;
    
