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

entity OB8_GPIO_top is
  generic (
    FSYS           : positive := 25_000_000;
    FSYS_INT       : positive := 25_000_000;
    NB_SWITCH      : positive := 8;
    NB_LED         : positive := 8;
    RESET_POLARITY : string   := "neg"       -- "pos" / "neg"
    );
  port (
    clk_i      : in  std_logic;
    arst_i     : in  std_logic;

    switch_i   : in  std_logic_vector(NB_SWITCH-1 downto 0);
    led_o      : out std_logic_vector(NB_LED   -1 downto 0)
);
end OB8_GPIO_top;

architecture rtl of OB8_GPIO_top is

  constant NB_LED0 : positive := 8;
  
  signal clk                          : std_logic;
  signal arst_b                       : std_logic;
  signal arst_b_sync                  : std_logic;
  signal led0                         : std_logic_vector(NB_LED0-1 downto 0);
  
begin  -- architecture rtl

  gen_arst_b:
  if RESET_POLARITY = "neg"
  generate
    arst_b <=     arst_i;
  end generate gen_arst_b;

  gen_arst:
  if RESET_POLARITY = "pos"
  generate
    arst_b <= not arst_i;
  end generate gen_arst;

  ins_reset_resynchronizer : entity work.sync2dffrn(rtl)
    port map(
    clk_i    => clk_i     ,
    arst_b_i => arst_b     ,
    d_i      => '1'       ,
    q_o      => arst_b_sync
    );
  
  ins_clock_divider : entity work.clock_divider(rtl)
    generic map(
      RATIO            => FSYS/FSYS_INT
      )
    port map (
      clk_i            => clk_i      ,
      arstn_i          => arst_b_sync,
      cke_i            => '1'        ,
      clk_div_o        => clk
      );

  ins_OB8_GPIO : entity work.OB8_GPIO(rtl)
    generic map (
      NB_SWITCH        => NB_SWITCH,
      NB_LED0          => NB_LED0
    )
    port map (
      clk_i      => clk        ,
      arst_b_i   => arst_b_sync,
      switch_i   => switch_i   ,
      led0_o     => led0
      );

  led_o <= led0;
    
end architecture rtl;
    
  
