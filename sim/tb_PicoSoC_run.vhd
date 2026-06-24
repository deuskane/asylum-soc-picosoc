-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_run
-- Project    : 
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_run.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2026-01-10
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2017 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2017-03-30  1.0      mrosiere Created
-- 2025-01-11  1.1      mrosiere Add fault test
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     std.textio.all;
library asylum;
use     asylum.PicoSoC_pkg.all;
library work;
  
entity tb_PicoSoC_run is
  generic
    (FSYS                  : positive := 50_000_000
    ;FSYS_INT              : positive := 50_000_000
    ;USER_NB_CPU           : positive  := 1
    ;USER_BAUD_RATE        : integer  := 115200
  --;USER_UART_DEPTH_TX    : natural  := 0
  --;USER_UART_DEPTH_RX    : natural  := 0
  --;USER_SPI_DEPTH_CMD    : natural  := 0
  --;USER_SPI_DEPTH_TX     : natural  := 0
  --;USER_SPI_DEPTH_RX     : natural  := 0
  --;USER_NB_SWITCH        : positive := 8
  --;USER_NB_LED0          : positive := 8
  --;USER_NB_LED1          : positive := 8
  --;RESET_POLARITY        : string   := "low"       -- "high" / "low"
    ;SUPERVISOR            : boolean  := True 
    ;USER_SAFETY           : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;USER_FAULT_INJECTION  : boolean  := True  
  --;USER_IT_POLARITY      : string   := "low"       -- "high" / "low"
  --;USER_FAULT_POLARITY   : string   := "low"       -- "high" / "low"
    ;DEBUG_ENABLE          : boolean  := True 
    ;CPU_MODEL             : string   := ""          -- "OpenBlaze8" / "WardRV_fsm"

    -- TB Parameters
    ;TB_WATCHDOG           : natural  := 10_000
    ;HAVE_SPI_MEMORY       : boolean  := False
     );
  
end entity tb_PicoSoC_run;

architecture tb of tb_PicoSoC_run is
  -- =====[ Parameters ]==========================
  constant TB_PERIOD               : time    := (1e9 / FSYS) * 1 ns;
  constant TB_WATCHDOG_TIME        : time    := TB_WATCHDOG * TB_PERIOD;

  constant USER_NB_SWITCH          : positive :=  8;
  constant USER_NB_LED0            : positive :=  8;
  constant USER_NB_LED1            : positive :=  8;

  constant RESET_POLARITY          : string   := "low";  -- "high" / "low"
  constant USER_IT_POLARITY        : string   := "high"; -- "high" / "low"
  constant USER_FAULT_POLARITY     : string   := "high"; -- "high" / "low"
  
  -- =====[ Dut Signals ]=========================
  signal  clk_i                    : std_logic := '0';
  signal  arst_b_i                 : std_logic;
  signal  switch_i                 : std_logic_vector(USER_NB_SWITCH-1 downto 0);
  signal  led0_o                   : std_logic_vector(USER_NB_LED0  -1 downto 0);
  signal  led1_o                   : std_logic_vector(USER_NB_LED1  -1 downto 0);
  signal  led_diff_o               : std_logic_vector(             3-1 downto 0);
  signal  it_user_i                : std_logic;
  signal  inject_error_i           : std_logic_vector(             3-1 downto 0);

  signal  spi_sclk_o               : std_logic;
  signal  spi_cs_b_o               : std_logic;
  signal  spi_mosi_o               : std_logic;
  signal  spi_miso_i               : std_logic;

  signal  RSTNeg                   : std_logic;
  signal  WPNeg                    : std_logic;
  signal  HOLDNeg                  : std_logic;
  signal  SNeg                     : std_logic;
  
  alias   led_switch               : std_logic_vector(USER_NB_SWITCH-1 downto 0) is led0_o(USER_NB_SWITCH-1 downto  0);
  alias   led_it                   : std_logic_vector(USER_NB_LED1  -1 downto 0) is led1_o;
  alias   led_diff                 : std_logic_vector(             3-1 downto 0) is led_diff_o;

  -- =====[ Test Signals ]========================
  signal  test_begin               : std_logic := '0';
  signal  test_done                : std_logic := '0';
  
  -- =====[ Functions ]===========================
  
  -------------------------------------------------------
  -- xrun
  -------------------------------------------------------
  procedure xrun
    (constant n     : in positive;           -- nb cycle
     constant pol   : in string;
     signal   clk   : in std_logic
     ) is
    
  begin
    for i in 0 to n-1
    loop
      if (pol="pos")
      then
        wait until rising_edge(clk);
      else
        wait until falling_edge(clk);
      end if;
      
    end loop;  -- i
  end xrun;

  -------------------------------------------------------
  -- run
  -------------------------------------------------------
  procedure run
    (constant n     : in positive;          -- nb cycle
     constant pol   : in string := "pos"
     ) is
    
  begin
    xrun(n,"pos",clk_i);
  end run;

begin  -- architecture tb

  -----------------------------------------------------
  -- Design Under Test
  -----------------------------------------------------
  dut : PicoSoC_top
    generic map
    (FSYS                  => FSYS            
    ,FSYS_INT              => FSYS_INT        
    ,USER_NB_CPU           => USER_NB_CPU
    ,USER_BAUD_RATE        => USER_BAUD_RATE
    ,USER_NB_SWITCH        => USER_NB_SWITCH       
    ,USER_NB_LED0          => USER_NB_LED0        
    ,USER_NB_LED1          => USER_NB_LED1        
    ,RESET_POLARITY        => RESET_POLARITY  
    ,SUPERVISOR            => SUPERVISOR      
    ,USER_SAFETY           => USER_SAFETY          
    ,USER_FAULT_INJECTION  => USER_FAULT_INJECTION 
    ,USER_IT_POLARITY      => USER_IT_POLARITY
    ,USER_FAULT_POLARITY   => USER_FAULT_POLARITY  
    ,CPU_MODEL             => CPU_MODEL
     )  
    port map
    (clk_i            => clk_i           
    ,arst_i           => arst_b_i        
    ,switch_i         => switch_i        
    ,led0_o           => led0_o
    ,led1_o           => led1_o
    ,led_diff_o       => led_diff_o
    ,it_user_i        => it_user_i     
    ,inject_error_i   => inject_error_i
    ,uart_tx_o        => open
    ,uart_rx_i        => '1'
    ,uart_cts_b_i     => '0'
    ,uart_rts_b_o     => open
    ,spi_sclk_o       => spi_sclk_o 
    ,spi_cs_b_o       => spi_cs_b_o 
    ,spi_mosi_o       => spi_mosi_o 
    ,spi_miso_i       => spi_miso_i
    ,debug_mux_i      => "000"
    ,debug_o          => open 
    ,debug_uart_tx_o  => open
    );

  -----------------------------------------------------
  -- Clock Tree
  -----------------------------------------------------
  clk_i <= not test_done and not clk_i after TB_PERIOD/2;

  ------------------------------------------------
  -- Memory Model
  ------------------------------------------------
  RSTNeg  <= '1';
  WPNeg   <= '1';
  HOLDNeg <= '1';
  SNeg    <= spi_cs_b_o when HAVE_SPI_MEMORY = true else
             '1';
  
  mem : entity work.m25p40(vhdl_behavioral)
      generic map
      (mem_file_name     => "memory.mem"
      ,UserPreload       => True
      ,DebugInfo         => True
      ,TimingChecksOn    => True
      ,MsgOn             => True
      ,XOn               => True
      ,LongTimming       => False
       )
      port map
      (D             => spi_mosi_o -- serial data input/IO0
      ,Q             => spi_miso_i -- serial data output/IO1
      ,C             => spi_sclk_o -- serial clock input
      ,SNeg          => SNeg   -- chip select input
      ,WNeg          => WPNeg  -- write protect input/IO2
      ,HOLDNeg       => HOLDNeg-- hold input/IO3
       );
  
  -----------------------------------------------------------------------------
  -- Watchdog
  -----------------------------------------------------------------------------
  p_watchdog: process is
  begin
    while (test_begin = '0')
    loop
      run(1);
    end loop;

    wait for TB_WATCHDOG_TIME;

    -- No testsuite just run
    test_done <= '1';
    run(1);
    
    assert (test_done = '1') report "[TESTBENCH] Test KO : Maximum cycle is reached" severity failure;

    -- end of process
    wait;
  end process;
  
  -----------------------------------------------------
  -- Test suite
  -----------------------------------------------------
  process is
  begin  -- process

      run(10);

      report "[TESTBENCH] Init signals";
      it_user_i      <= '0';             -- active low
      inject_error_i <= (others => '0'); -- active low

      report "[TESTBENCH] Reset Sequence"; 
      arst_b_i       <= '0';

      if HAVE_SPI_MEMORY = true
      then
        wait for 10 ms;
      end if;
      
      run(1);

      test_begin     <= '1';
      arst_b_i       <= '1';
      wait;
  end process;

end architecture tb;
