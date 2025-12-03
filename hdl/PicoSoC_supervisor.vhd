-------------------------------------------------------------------------------
-- Title      : PicoSoC_supervisor
-- Project    : 
-------------------------------------------------------------------------------
-- File       : PicoSoC_supervisor.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2025-12-03
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2017 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2025-01-01  1.0      mrosiere Created
-- 2025-04-02  1.1      mrosiere Add ICN
-- 2025-07-05  1.2      mrosiere Use GIC instead GPIO
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.sbi_pkg.all;
use     asylum.GPIO_csr_pkg.all;
use     asylum.GIC_csr_pkg.all;
use     asylum.PicoSoC_pkg.all;
use     asylum.OpenBlaze8_pkg.all;
use     asylum.gpio_pkg.all;
use     asylum.gic_pkg.all;
use     asylum.icn_pkg.all;

entity PicoSoC_supervisor is
  generic
    (NB_LED0               : positive := 8
    ;NB_LED1               : positive := 8

    ;ICN_ALGO_SEL          : string := "or"
    );
  port
    (clk_i                 : in  std_logic
    ;arst_b_i              : in  std_logic
                          
    ;led0_o                : out std_logic_vector(NB_LED0  -1 downto 0)
    ;led1_o                : out std_logic_vector(NB_LED1  -1 downto 0)
                          
    ;diff_i                : in  std_logic_vector(        3-1 downto 0)
                          
    ;debug_o               : out PicoSoC_supervisor_debug_t
     );
end PicoSoC_supervisor;

architecture rtl of PicoSoC_supervisor is
  -- Constant declaration
  constant CST0                       : std_logic_vector (8-1 downto 0) := (others => '0');
  constant CST1                       : std_logic_vector (8-1 downto 0) := (others => '1');

  -- ICN Configuration
  constant TARGET_ADDR_ENCODING       : string   := PICOSOC_SUPERVISOR_ADDR_ENCODING;

  constant TARGET_LED0                : integer  := 0;
  constant TARGET_LED1                : integer  := 1;
  constant TARGET_GIC                 : integer  := 2;

  constant NB_TARGET                  : positive := 3;

  constant TARGET_ID                  : sbi_addrs_t   (NB_TARGET-1 downto 0) :=
    ( TARGET_LED0                     => PICOSOC_SUPERVISOR_LED0_BA,
      TARGET_LED1                     => PICOSOC_SUPERVISOR_LED1_BA,
      TARGET_GIC                      => PICOSOC_SUPERVISOR_GIC_BA 
      );

  constant TARGET_ADDR_WIDTH          : naturals_t    (NB_TARGET-1 downto 0) :=
    ( TARGET_LED0                     => GPIO_ADDR_WIDTH,
      TARGET_LED1                     => GPIO_ADDR_WIDTH,
      TARGET_GIC                      => GIC_ADDR_WIDTH
      );
      
  -- Signals Clock/Reset
  signal clk                          : std_logic;
  signal arst_b                       : std_logic;
  
  -- Signals CPUs
  signal cpu_ics                      : std_logic;
  signal cpu_iaddr                    : std_logic_vector(10-1 downto 0);
  signal cpu_idata                    : std_logic_vector(17 downto 0);
  
  signal cpu_sbi_ini                  : sbi_ini_t(addr (SBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(SBI_DATA_WIDTH-1 downto 0));
  signal cpu_sbi_tgt                  : sbi_tgt_t(rdata(SBI_DATA_WIDTH-1 downto 0));

  signal cpu_it_val                   : std_logic;
--signal cpu_it_ack                   : std_logic;

  -- Signals ICN
  signal icn_sbi_inis                 : sbi_inis_t(NB_TARGET-1 downto 0)(addr (SBI_ADDR_WIDTH-1 downto 0),
                                                                         wdata(SBI_DATA_WIDTH-1 downto 0));
  signal icn_sbi_tgts                 : sbi_tgts_t(NB_TARGET-1 downto 0)(rdata(SBI_DATA_WIDTH-1 downto 0));
  
  signal led0                         : std_logic_vector(NB_LED0-1 downto 0);
  signal led1                         : std_logic_vector(NB_LED1-1 downto 0);
  
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
    ,arstn_i              => arst_b   
    ,ics_o                => cpu_ics  
    ,iaddr_o              => cpu_iaddr
    ,idata_i              => cpu_idata
    ,sbi_ini_o            => cpu_sbi_ini  
    ,sbi_tgt_i            => cpu_sbi_tgt  
    ,interrupt_i          => cpu_it_val   
    ,interrupt_ack_o      => open
    );

  -----------------------------------------------------------------------------
  -- CPU ROM
  -----------------------------------------------------------------------------
  ins_sbi_OpenBlaze8_ROM : entity asylum.ROM_supervisor(rom)
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
  -- GPIO 0 - LED
  -- Used as resetb for soc user
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
    ,data_i               => CST0(NB_LED0-1 downto 0)
    ,data_o               => led0        
    ,data_oe_o            => open        
    ,interrupt_o          => open        
    ,interrupt_ack_i      => '0'
    );

  -----------------------------------------------------------------------------
  -- GPIO 1 - LED
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
    ,data_i               => CST0(NB_LED1-1 downto 0)
    ,data_o               => led1        
    ,data_oe_o            => open        
    ,interrupt_o          => open        
    ,interrupt_ack_i      => '0'
    );

  -----------------------------------------------------------------------------
  -- GIC - Interruption Vector
  -----------------------------------------------------------------------------
  ins_sbi_gic : sbi_GIC
    port map
    (clk_i                => clk         
    ,arst_b_i             => arst_b      
    ,sbi_ini_i            => icn_sbi_inis(TARGET_GIC)
    ,sbi_tgt_o            => icn_sbi_tgts(TARGET_GIC)
    ,its_i                => diff_i      
    ,itm_o                => cpu_it_val
    );
  
  -----------------------------------------------------------------------------
  -- Output
  -----------------------------------------------------------------------------
  led0_o <= led0;
  led1_o <= led1;

  -----------------------------------------------------------------------------
  -- Debug
  -----------------------------------------------------------------------------
  debug_o.arst_b <= arst_b;
  
end architecture rtl;
    
  
