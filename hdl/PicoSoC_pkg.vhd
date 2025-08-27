-------------------------------------------------------------------------------
-- Title      : PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : PicoSoC.vhd
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

package PicoSoC_pkg is

  -----------------------------------------------------------------------------
  -- PicoSoC_user_debug_t
  --
  -- Struct with internal signal of SoC User
  -----------------------------------------------------------------------------

  type PicoSoC_user_debug_t is record
    arst_b      : std_logic;
    cpu_iaddr   : std_logic_vector(10-1 downto 0);
    cpu_idata   : std_logic_vector(18-1 downto 0);
                
    cpu_dcs     : std_logic;
    cpu_dre     : std_logic;
    cpu_dwe     : std_logic;
    cpu_daddr   : std_logic_vector( 8-1 downto 0);
    cpu_dbusy   : std_logic;

    switch_cs   : std_logic;
    switch_busy : std_logic;
    led0_cs     : std_logic;
    led0_busy   : std_logic;
    led1_cs     : std_logic;
    led1_busy   : std_logic;
    uart_cs     : std_logic;
    uart_busy   : std_logic;
    spi_cs      : std_logic;
    spi_busy    : std_logic;
    
  end record PicoSoC_user_debug_t;

  -----------------------------------------------------------------------------
  -- PicoSoC_supervisor_debug_t
  --
  -- Struct with internal signal of SoC Supervisor
  -----------------------------------------------------------------------------
  type PicoSoC_supervisor_debug_t is record
    arst_b : std_logic;
  end record PicoSoC_supervisor_debug_t;
  
  -----------------------------------------------------------------------------
  -- Component
  -----------------------------------------------------------------------------
  component PicoSoC_supervisor 
    generic (
      NB_LED0               : positive;
      NB_LED1               : positive;

      ICN_ALGO_SEL          : string
      );
    port (
      clk_i                 : in  std_logic;
      arst_b_i              : in  std_logic;
                            
      led0_o                : out std_logic_vector(NB_LED0  -1 downto 0);
      led1_o                : out std_logic_vector(NB_LED1  -1 downto 0);
                            
      diff_i                : in  std_logic_vector(        3-1 downto 0);

      debug_o               : out PicoSoC_supervisor_debug_t
      );
  end component;

  component PicoSoC_user
    generic (
      CLOCK_FREQ            : integer  ;
      BAUD_RATE             : integer  ;
      UART_DEPTH_TX         : natural  ;
      UART_DEPTH_RX         : natural  ;
      SPI_DEPTH_CMD         : natural  ;
      SPI_DEPTH_TX          : natural  ;
      SPI_DEPTH_RX          : natural  ;
      NB_SWITCH             : positive ;
      NB_LED0               : positive ;
      NB_LED1               : positive ;
      SAFETY                : string   ;
      FAULT_INJECTION       : boolean  ;
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
      uart_cts_b_i          : in  std_logic; -- Clear   To Send (Active low)
      uart_rts_b_o          : out std_logic; -- Request To Send (Active low)
                            
      spi_sclk_o            : out std_logic;
      spi_cs_b_o            : out std_logic;
      spi_mosi_o            : out std_logic;
      spi_miso_i            : in  std_logic;
                            
      it_i                  : in  std_logic;
      inject_error_i        : in  std_logic_vector(        3-1 downto 0);
      diff_o                : out std_logic_vector(        3-1 downto 0); -- bit 0 : cpu0 vs cpu1
                                                                          -- bit 1 : cpu1 vs cpu2
                                                                          -- bit 2 : cpu2 vs cpu0

      debug_o               : out PicoSoC_user_debug_t
      );
  end component;
end package PicoSoC_pkg;
