-------------------------------------------------------------------------------
-- Title      : PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : PicoSoC.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2025-01-15
-- Last update: 2025-11-04
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
library asylum;
use     asylum.PicoSoC_pkg.all;

library asylum;
use     asylum.ON_CHIP_ANALYZER_PACKAGE_NxChipscope_wrapper.all;

entity PicoSoC_scope is
    Port (
      CLK                 : in  std_logic;
      ENA                 : in  std_logic;

      -- USER DATA
      TRIG_LINES          : in  std_logic_vector(0 downto 0);
      DATA_LINES          : in  std_logic_vector(23 downto 0);

      TRIG_IMMEDIATE_EXT  : in  std_logic;

      -- Debug interface
      TRIG_ARMED          : out std_logic;
      FIRST_LEVEL_TRIG_OK : out std_logic;
      CURRENT_CAPTURE_SET : out std_logic_vector(3 downto 0);
      DONE                : out std_logic
      );
end PicoSoC_scope;
  
architecture rtl of PicoSoC_scope is
  
  component NxChipscope_wrapper
    Port (
      CLK                 : in  std_logic;
      ENA                 : in  std_logic;

      -- USER DATA
      TRIG_LINES          : in  std_logic_vector(0 downto 0);
      DATA_LINES          : in  std_logic_vector(23 downto 0);

      TRIG_IMMEDIATE_EXT  : in  std_logic;

      -- Debug interface
      TRIG_ARMED          : out std_logic;
      FIRST_LEVEL_TRIG_OK : out std_logic;
      CURRENT_CAPTURE_SET : out std_logic_vector(3 downto 0);
      DONE                : out std_logic
      );
  end component;

begin  -- architecture rtl

  ins_NxChipscope_wrapper : NxChipscope_wrapper
    port map
      (CLK                 => CLK                
      ,ENA                 => ENA                
      ,TRIG_LINES          => TRIG_LINES         
      ,DATA_LINES          => DATA_LINES         
      ,TRIG_IMMEDIATE_EXT  => TRIG_IMMEDIATE_EXT 
      ,TRIG_ARMED          => TRIG_ARMED         
      ,FIRST_LEVEL_TRIG_OK => FIRST_LEVEL_TRIG_OK
      ,CURRENT_CAPTURE_SET => CURRENT_CAPTURE_SET
      ,DONE                => DONE               
      );
  
end architecture rtl;
