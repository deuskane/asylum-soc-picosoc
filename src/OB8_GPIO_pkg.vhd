-------------------------------------------------------------------------------
-- Title      : OB8_GPIO
-- Project    : 
-------------------------------------------------------------------------------
-- File       : OB8_GPIO.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2025
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2025-04-14  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package OB8_GPIO_pkg is


  type OB8_GPIO_user_debug_t is record
    arst_b    : std_logic;
    cpu_iaddr : std_logic_vector(10-1 downto 0);
    cpu_idata : std_logic_vector(18-1 downto 0);
  end record OB8_GPIO_user_debug_t;

  type OB8_GPIO_supervisor_debug_t is record
    arst_b : std_logic;
  end record OB8_GPIO_supervisor_debug_t;
  
  component OB8_GPIO_supervisor 
    generic (
      NB_LED0               : positive;
      NB_LED1               : positive;

      TARGET_ADDR_ENCODING  : string  ;
      ICN_ALGO_SEL          : string
      );
    port (
      clk_i                 : in  std_logic;
      arst_b_i              : in  std_logic;
                            
      led0_o                : out std_logic_vector(NB_LED0  -1 downto 0);
      led1_o                : out std_logic_vector(NB_LED1  -1 downto 0);
                            
      diff_i                : in  std_logic_vector(        3-1 downto 0);

      debug_o               : out OB8_GPIO_supervisor_debug_t
      );
  end component;


  component OB8_GPIO_user
    generic (
      CLOCK_FREQ            : integer  ;
      BAUD_RATE             : integer  ;
      NB_SWITCH             : positive ;
      NB_LED0               : positive ;
      NB_LED1               : positive ;
      SAFETY                : string   ;
      FAULT_INJECTION       : boolean  ;
      TARGET_ADDR_ENCODING  : string   ;
      ICN_ALGO_SEL          : string   
      );
    port (
      clk_i                 : in  std_logic;
      arst_b_i              : in  std_logic;
                            
      switch_i              : in  std_logic_vector(NB_SWITCH-1 downto 0);
      led0_o                : out std_logic_vector(NB_LED0  -1 downto 0);
      led1_o                : out std_logic_vector(NB_LED1  -1 downto 0);
                            
      uart_tx_o             : out std_logic;
      uart_rx_i             : in  std_logic;
                            
                            
      it_i                  : in  std_logic;
      inject_error_i        : in  std_logic_vector(        3-1 downto 0);
      diff_o                : out std_logic_vector(        3-1 downto 0); -- bit 0 : cpu0 vs cpu1
                                                                          -- bit 1 : cpu1 vs cpu2
                                                                          -- bit 2 : cpu2 vs cpu0

      debug_o               : out OB8_GPIO_user_debug_t
      );
  end component;
end package OB8_GPIO_pkg;
