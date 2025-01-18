-------------------------------------------------------------------------------
-- Title      : OB8_GPIO_supervisor
-- Project    : 
-------------------------------------------------------------------------------
-- File       : OB8_GPIO_supervisor.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2025-01-15
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2017 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2017-03-30  1.0      mrosiere	Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.pbi_pkg.all;

entity OB8_GPIO_supervisor is
  generic (
    NB_LED0        : positive := 8;
    NB_LED1        : positive := 8
    );
  port (
    clk_i      : in  std_logic;
    arst_b_i   : in  std_logic;

    led0_o     : out std_logic_vector(NB_LED0  -1 downto 0);
    led1_o     : out std_logic_vector(NB_LED1  -1 downto 0);

    diff_i     : in  std_logic_vector(        3-1 downto 0)
);
end OB8_GPIO_supervisor;

architecture rtl of OB8_GPIO_supervisor is
  constant ID_LED0                    : std_logic_vector (PBI_ADDR_WIDTH-1 downto 0) := "00000000";
  --                                                                                    "00000011"
  constant ID_LED1                    : std_logic_vector (PBI_ADDR_WIDTH-1 downto 0) := "00000100";
  --                                                                                    "00000011"
  constant ID_IT_VECTOR_MASK          : std_logic_vector (PBI_ADDR_WIDTH-1 downto 0) := "00001000";
  --                                                                                    "00000011"
  constant ID_IT_VECTOR               : std_logic_vector (PBI_ADDR_WIDTH-1 downto 0) := "00001100";
  --                                                                                    "00000011"

  constant CST0                       : std_logic_vector (8-1 downto 0) := (others => '0');
  constant CST1                       : std_logic_vector (8-1 downto 0) := (others => '1');
  
  signal clk                          : std_logic;
  signal arst_b                        : std_logic;
  
  signal iaddr                        : std_logic_vector(10-1 downto 0);
  signal idata                        : std_logic_vector(17 downto 0);
  signal pbi_ini                      : pbi_ini_t;
  signal pbi_tgt                      : pbi_tgt_t;
  signal pbi_tgt_led0                 : pbi_tgt_t;
  signal pbi_tgt_led1                 : pbi_tgt_t;
  signal pbi_tgt_it_vector_mask       : pbi_tgt_t;
  signal pbi_tgt_it_vector            : pbi_tgt_t;
  
  signal it_val                       : std_logic;
  signal it_ack                       : std_logic;

  signal led0                         : std_logic_vector(NB_LED0-1 downto 0);
  signal led1                         : std_logic_vector(NB_LED1-1 downto 0);

  signal diff_mask                    : std_logic_vector(      3-1 downto 0);
  
begin  -- architecture rtl

  -- Clock & Reset
  clk    <= clk_i;
  arst_b <= arst_b_i;
  
  ins_pbi_OpenBlaze8_0 : entity work.pbi_OpenBlaze8(rtl)
  port map (
    clk_i            => clk      ,
    cke_i            => '1'      ,
    arstn_i          => arst_b   ,
    iaddr_o          => iaddr    ,
    idata_i          => idata    ,
    pbi_ini_o        => pbi_ini  ,
    pbi_tgt_i        => pbi_tgt  ,
    interrupt_i      => it_val   ,
    interrupt_ack_o  => open
    );

  pbi_tgt <= pbi_tgt_led0           or
             pbi_tgt_led1           or
             pbi_tgt_it_vector_mask or
             pbi_tgt_it_vector
             ;

  ins_pbi_OpenBlaze8_ROM : entity work.ROM_supervisor(rom)
    port map (
      clk_i            => clk    ,
      cke_i            => '1'    ,
      address_i        => iaddr  ,
      instruction_o    => idata  
    );

  ins_pbi_led0 : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => NB_LED0,
    DATA_OE_INIT     => CST1(NB_LED0-1 downto 0),
    DATA_OE_FORCE    => CST1(NB_LED0-1 downto 0),
    IT_ENABLE        => false, -- GPIO can generate interruption
    ID               => ID_LED0
    )
  port map  (
    clk_i            => clk         ,
    cke_i            => '1'         ,
    arstn_i          => arst_b      ,
    pbi_ini_i        => pbi_ini     ,
    pbi_tgt_o        => pbi_tgt_led0,
    data_i           => CST0(NB_LED0-1 downto 0),
    data_o           => led0        ,
    data_oe_o        => open        ,
    interrupt_o      => open        ,
    interrupt_ack_i  => '0'
    );

  ins_pbi_led1 : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => NB_LED1,
    DATA_OE_INIT     => CST1(NB_LED1-1 downto 0),
    DATA_OE_FORCE    => CST1(NB_LED1-1 downto 0),
    IT_ENABLE        => false, -- GPIO can generate interruption
    ID               => ID_LED1
    )
  port map  (
    clk_i            => clk         ,
    cke_i            => '1'         ,
    arstn_i          => arst_b      ,
    pbi_ini_i        => pbi_ini     ,
    pbi_tgt_o        => pbi_tgt_led1,
    data_i           => CST0(NB_LED1-1 downto 0),
    data_o           => led1        ,
    data_oe_o        => open        ,
    interrupt_o      => open        ,
    interrupt_ack_i  => '0'
    );

  ins_pbi_it_vector_mask : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => 3,
    DATA_OE_INIT     => CST1(3-1 downto 0),
    DATA_OE_FORCE    => CST1(3-1 downto 0),
    IT_ENABLE        => false, -- GPIO can generate interruption
    ID               => ID_IT_VECTOR_MASK
    )
  port map  (
    clk_i            => clk         ,
    cke_i            => '1'         ,
    arstn_i          => arst_b      ,
    pbi_ini_i        => pbi_ini     ,
    pbi_tgt_o        => pbi_tgt_it_vector_mask,
    data_i           => CST0(3-1 downto 0),
    data_o           => diff_mask   ,
    data_oe_o        => open        ,
    interrupt_o      => open        ,
    interrupt_ack_i  => '0'
    );

  ins_pbi_it_vector : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => 3,
    DATA_OE_INIT     => CST0(3-1 downto 0),
    DATA_OE_FORCE    => CST1(3-1 downto 0),
    IT_ENABLE        => false, -- GPIO can generate interruption
    ID               => ID_IT_VECTOR
    )
  port map  (
    clk_i            => clk         ,
    cke_i            => '1'         ,
    arstn_i          => arst_b      ,
    pbi_ini_i        => pbi_ini     ,
    pbi_tgt_o        => pbi_tgt_it_vector,
    data_i           => diff_i      ,
    data_o           => open        ,
    data_oe_o        => open        ,
    interrupt_o      => open        ,
    interrupt_ack_i  => '0'
    );

  led0_o <= led0;
  led1_o <= led1;

  it_val <= ((diff_i(0) and diff_mask(0)) or
             (diff_i(1) and diff_mask(1)) or
             (diff_i(2) and diff_mask(2)));
  
end architecture rtl;
    
  
