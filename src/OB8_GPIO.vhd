-------------------------------------------------------------------------------
-- Title      : OB8_GPIO
-- Project    : 
-------------------------------------------------------------------------------
-- File       : OB8_GPIO.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2025-01-06
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
-- 2024-12-31  1.0      mrosiere Fix parameter to GPIO
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.pbi_pkg.all;

entity OB8_GPIO is
  generic (
    NB_SWITCH      : positive := 8;
    NB_LED0        : positive := 8
    );
  port (
    clk_i      : in  std_logic;
    arst_b_i   : in  std_logic;

    switch_i   : in  std_logic_vector(NB_SWITCH-1 downto 0);
    led0_o     : out std_logic_vector(NB_LED0  -1 downto 0)
);
end OB8_GPIO;

architecture rtl of OB8_GPIO is
  constant ID_SWITCH                  : std_logic_vector (PBI_ADDR_WIDTH-1 downto 0) := "00000000";
  --                                                                                    "00000011"
  constant ID_LED0                    : std_logic_vector (PBI_ADDR_WIDTH-1 downto 0) := "00000100";
  --                                                                                    "00000011"

  constant cst0                       : std_logic_vector (8-1 downto 0) := (others => '0');
  constant cst1                       : std_logic_vector (8-1 downto 0) := (others => '1');
    
  signal iaddr                        : std_logic_vector(10-1 downto 0);
  signal idata                        : std_logic_vector(17 downto 0);
  signal pbi_ini                      : pbi_ini_t;
  signal pbi_tgt                      : pbi_tgt_t;
  signal pbi_tgt_switch               : pbi_tgt_t;
  signal pbi_tgt_led0                 : pbi_tgt_t;

begin  -- architecture rtl

  ins_pbi_OpenBlaze8 : entity work.pbi_OpenBlaze8(rtl)
  port map (
    clk_i            => clk_i     ,
    cke_i            => '1'       ,
    arstn_i          => arst_b_i  ,
    iaddr_o          => iaddr     ,
    idata_i          => idata     ,
    pbi_ini_o        => pbi_ini   ,
    pbi_tgt_i        => pbi_tgt   ,
    interrupt_i      => '0'       ,
    interrupt_ack_o  => open 
    );

  pbi_tgt.rdata <= pbi_tgt_switch.rdata or
                   pbi_tgt_led0  .rdata;
  pbi_tgt.busy  <= pbi_tgt_switch.busy  or
                   pbi_tgt_led0  .busy;

  ins_pbi_OpenBlaze8_ROM : entity work.OpenBlaze8_ROM(rtl)
    port map (
      clk_i            => clk_i  ,
      cke_i            => '1'    ,
      address_i        => iaddr  ,
      instruction_o    => idata  
    );
  
  ins_pbi_switch : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => NB_SWITCH,
    DATA_OE_INIT     => cst0(NB_SWITCH-1 downto 0),
    DATA_OE_FORCE    => cst1(NB_SWITCH-1 downto 0),
    IT_ENABLE        => false, -- GPIO can't generate interruption
    ID               => ID_SWITCH
    )
  port map  (
    clk_i            => clk_i         ,
    cke_i            => '1'           ,
    arstn_i          => arst_b_i      ,
    pbi_ini_i        => pbi_ini       ,
    pbi_tgt_o        => pbi_tgt_switch,
    data_i           => switch_i      ,
    data_o           => open          ,
    data_oe_o        => open          ,
    interrupt_o      => open          ,
    interrupt_ack_i  => '0'
    );

  ins_pbi_led0 : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => NB_LED0,
    DATA_OE_INIT     => cst1(NB_LED0-1 downto 0),
    DATA_OE_FORCE    => cst1(NB_LED0-1 downto 0),
    IT_ENABLE        => false, -- GPIO can't generate interruption
    ID               => ID_LED0
    )
  port map  (
    clk_i            => clk_i       ,
    cke_i            => '1'         ,
    arstn_i          => arst_b_i    ,
    pbi_ini_i        => pbi_ini     ,
    pbi_tgt_o        => pbi_tgt_led0,
    data_i           => X"00"       ,
    data_o           => led0_o      ,
    data_oe_o        => open        ,
    interrupt_o      => open        ,
    interrupt_ack_i  => '0'
    );

end architecture rtl;
    
  
