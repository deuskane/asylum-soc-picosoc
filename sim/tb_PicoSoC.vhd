-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2025-09-06
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
library work;
use     work.PicoSoC_pkg.all;
  
entity tb_PicoSoC is
  generic
    (FSYS             : positive := 50_000_000
    ;FSYS_INT         : positive := 50_000_000
    ;BAUD_RATE        : integer  := 115200
  --;UART_DEPTH_TX    : natural  := 0
  --;UART_DEPTH_RX    : natural  := 0
  --;SPI_DEPTH_CMD    : natural  := 0
  --;SPI_DEPTH_TX     : natural  := 0
  --;SPI_DEPTH_RX     : natural  := 0
  --;NB_SWITCH        : positive := 8
  --;NB_LED           : positive := 19
  --;RESET_POLARITY   : string   := "low"       -- "high" / "low"
    ;SUPERVISOR       : boolean  := True 
    ;SAFETY           : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;FAULT_INJECTION  : boolean  := True  
  --;IT_USER_POLARITY : string   := "low"       -- "high" / "low"
  --;FAULT_POLARITY   : string   := "low"       -- "high" / "low"
    ;DEBUG_ENABLE     : boolean  := True 

    -- TB Parameters
    ;TB_WATCHDOG      : natural  := 10_000
    ;HAVE_SPI_MEMORY  : boolean  := False
     );
  
end entity tb_PicoSoC;

architecture tb of tb_PicoSoC is
  -- =====[ Parameters ]==========================
  constant TB_PERIOD               : time    := (1e9 / FSYS) * 1 ns;
  constant TB_WATCHDOG_TIME        : time    := TB_WATCHDOG * TB_PERIOD;

  constant NB_SWITCH               : positive :=  8;
  constant NB_LED                  : positive := 19;

  constant RESET_POLARITY          : string   := "low";  -- "high" / "low"
  constant IT_USER_POLARITY        : string   := "high"; -- "high" / "low"
  constant FAULT_POLARITY          : string   := "high"; -- "high" / "low"
  
  -- =====[ Dut Signals ]=========================
  signal  clk_i                    : std_logic := '0';
  signal  arst_b_i                 : std_logic;
  signal  switch_i                 : std_logic_vector(NB_SWITCH-1 downto 0);
  signal  led_o                    : std_logic_vector(NB_LED   -1 downto 0);
  signal  it_user_i                : std_logic;
  signal  inject_error_i           : std_logic_vector(        3-1 downto 0);

  signal  spi_sclk_o               : std_logic;
  signal  spi_cs_b_o               : std_logic;
  signal  spi_mosi_o               : std_logic;
  signal  spi_miso_i               : std_logic;

  signal  RSTNeg                   : std_logic;
  signal  WPNeg                    : std_logic;
  signal  HOLDNeg                  : std_logic;
  signal  SNeg                     : std_logic;
  
  alias   led_switch               : std_logic_vector(NB_SWITCH-1 downto 0) is led_o(NB_SWITCH-1 downto  0);
  alias   led_it                   : std_logic_vector(        8-1 downto 0) is led_o(       16-1 downto  8);
  alias   led_diff                 : std_logic_vector(        3-1 downto 0) is led_o(       19-1 downto 16);

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
    (FSYS             => FSYS            
    ,FSYS_INT         => FSYS_INT        
    ,BAUD_RATE        => BAUD_RATE
    ,NB_SWITCH        => NB_SWITCH       
    ,NB_LED           => NB_LED          
    ,RESET_POLARITY   => RESET_POLARITY  
    ,SUPERVISOR       => SUPERVISOR      
    ,SAFETY           => SAFETY          
    ,FAULT_INJECTION  => FAULT_INJECTION 
    ,IT_USER_POLARITY => IT_USER_POLARITY
    ,FAULT_POLARITY   => FAULT_POLARITY  
     )  
    port map
    (clk_i            => clk_i           
    ,arst_i           => arst_b_i        
    ,switch_i         => switch_i        
    ,led_o            => led_o           
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
      
      report "[TESTBENCH] Change Switch" ;
      switch_i       <= (others => '0');
      for i in NB_SWITCH-1 downto 0 loop
        switch_i(i)    <= '1';
        wait until (led_switch = switch_i) ;
        
      end loop;  -- i

      report "[TESTBENCH] User Interruption" ;
      run(1,"neg");
      it_user_i        <= '1';
      run(1,"neg");
      it_user_i        <= '0';
      run(1000);

      run(1,"neg");
      it_user_i        <= '1';
      run(100);
      run(1,"neg");
      it_user_i        <= '0';
      run(1000);
      
      if (FAULT_INJECTION and SAFETY="lock-step")
      then
        report "[TESTBENCH] Inject error (lock-step)" ;
        assert led_diff = "000" report "Bad value of led_diff" severity failure;
        
        report "[TESTBENCH] Inject error in CPU0" ;
        inject_error_i(0) <= '1';
        run(100);
        inject_error_i(0) <= '0';

        while (not (led_switch /= switch_i))
        loop
          run(1);
        end loop;
        while (not (led_switch  = switch_i))
        loop
          run(1);
        end loop;

        report "[TESTBENCH] Inject error in CPU1" ;
        inject_error_i(1) <= '1';
        run(100);
        inject_error_i(1) <= '0';

        while (not (led_switch /= switch_i))
        loop
          run(1);
        end loop;
        while (not (led_switch  = switch_i))
        loop
          run(1);
        end loop;

        report "[TESTBENCH] Inject error in CPU0 in continue" ;
        inject_error_i(1) <= '1';
        run(100);
        inject_error_i(1) <= '0';

      end if;

      if (FAULT_INJECTION and SAFETY="tmr")
      then
        report "[TESTBENCH] Inject error (TMR)" ;
        assert led_diff = "000" report "Bad value of led_diff" severity failure;
        
        report "[TESTBENCH] Inject error in CPU0" ;
        inject_error_i(0) <= '1';
        run(100);
        inject_error_i(0) <= '0';

        run(100);
        assert led_switch  = switch_i report "Bad value of led_switch" severity failure;
        assert led_diff    = "000"    report "Bad value of led_diff"   severity failure;

        report "[TESTBENCH] Inject error in CPU1" ;
        inject_error_i(1) <= '1';
        run(100);
        inject_error_i(1) <= '0';

        while (not (led_switch /= switch_i))
        loop
          run(1);
        end loop;
        while (not (led_switch  = switch_i))
        loop
          run(1);
        end loop;

        assert led_switch  = switch_i report "Bad value of led_switch" severity failure;
        assert led_diff    = "001"    report "Bad value of led_diff"   severity failure;

        report "[TESTBENCH] Inject error in CPU2" ;
        inject_error_i(2) <= '1';
        run(100);
        inject_error_i(2) <= '0';

        run(100);
        assert led_switch  = switch_i report "Bad value of led_switch" severity failure;
        assert led_diff    = "001"    report "Bad value of led_diff"   severity failure;

        report "[TESTBENCH] Inject error in CPU2" ;
        inject_error_i(2) <= '1';
        run(100);
        inject_error_i(2) <= '0';

        run(100);
        assert led_switch  = switch_i report "Bad value of led_switch" severity failure;
        assert led_diff    = "001"    report "Bad value of led_diff"   severity failure;
        
        report "[TESTBENCH] Inject error in CPU1" ;
        inject_error_i(1) <= '1';
        run(100);
        inject_error_i(1) <= '0';

        while (not (led_switch /= switch_i))
        loop
          run(1);
        end loop;
        while (not (led_switch  = switch_i))
        loop
          run(1);
        end loop;

        assert led_diff    = "010"    report "Bad value of led_diff"   severity failure;
        
        report "[TESTBENCH] Inject error in CPU0 in continue" ;
        inject_error_i(1) <= '1';
        run(100);
        inject_error_i(1) <= '0';

        assert led_switch  = switch_i report "Bad value of led_switch" severity failure;
        assert led_diff    = "010"    report "Bad value of led_diff"   severity failure;

      end if;
        
      report "[TESTBENCH] Test OK";
      test_done <= '1';
      wait;
  end process;


end architecture tb;
