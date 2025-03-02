-------------------------------------------------------------------------------
-- Title      : tb_OB8_GPIO
-- Project    : 
-------------------------------------------------------------------------------
-- File       : tb_OB8_GPIO.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2025-03-02
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
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_OB8_GPIO is
  generic
    (SUPERVISOR       : boolean  := True
    ;SAFETY           : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;FAULT_INJECTION  : boolean  := True
    ;TB_WATCHDOG      : natural  := 10_000
    ;BAUD_RATE        : integer  := 115200
     );
  
end entity tb_OB8_GPIO;

architecture tb of tb_OB8_GPIO is
  -- =====[ Parameters ]==========================
  constant TB_PERIOD               : time    := 40 ns;
--constant TB_WATCHDOG             : natural := 10000;

  constant FSYS                    : positive := 25_000_000;
  constant FSYS_INT                : positive := 25_000_000;
  constant NB_SWITCH               : positive :=  8;
  constant NB_LED                  : positive := 19;

  constant RESET_POLARITY          : string   := "low";  -- "high" / "low"
  constant IT_USER_POLARITY        : string   := "high"; -- "high" / "low"
  constant FAULT_POLARITY          : string   := "high"; -- "high" / "low"
  
  -- =====[ Dut Signals ]=========================
  signal clk_i                     : std_logic := '0';
  signal arst_b_i                  : std_logic;
  signal switch_i                  : std_logic_vector(NB_SWITCH-1 downto 0);
  signal led_o                     : std_logic_vector(NB_LED   -1 downto 0);
  signal it_user_i                 : std_logic;
  signal inject_error_i            : std_logic_vector(        3-1 downto 0);
                                   
  alias  led_switch                : std_logic_vector(NB_SWITCH-1 downto 0) is led_o(NB_SWITCH-1 downto  0);
  alias  led_it                    : std_logic_vector(        8-1 downto 0) is led_o(       19-1 downto 11);
  alias  led_diff                  : std_logic_vector(        3-1 downto 0) is led_o(       11-1 downto  8);

  -- =====[ Test Signals ]========================
  signal test_done                 : std_logic := '0';
  signal test_ok                   : std_logic := '0';
  
  -- =====[ Functions ]===========================
  
  -------------------------------------------------------
  -- xrun
  -------------------------------------------------------
  procedure xrun
    (constant n     : in positive;           -- nb cycle
     constant pol   : in string;
     signal   clk_i : in std_logic
     ) is
    
  begin
    for i in 0 to n-1
    loop
      if (pol="pos")
      then
        wait until rising_edge(clk_i);
      else
        wait until falling_edge(clk_i);
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
  dut : entity work.OB8_GPIO_top(rtl)
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
    );

  -----------------------------------------------------
  -- Clock Tree
  -----------------------------------------------------
  clk_i <= not test_done and not clk_i after TB_PERIOD/2;

  -----------------------------------------------------------------------------
  -- Watchdog
  -----------------------------------------------------------------------------
  p_watchdog: process is
  begin
    run(TB_WATCHDOG);

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
      run(1);
      arst_b_i       <= '1';
      
      report "[TESTBENCH] Change Switch" ;
      for i in 0 to NB_SWITCH-1 loop
        switch_i       <= (others => '0');
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
        report "[TESTBENCH] Inject error" ;
        assert led_diff = "000" report "Bad value of led_diff" severity failure;
        
        report "[TESTBENCH] Inject error in CPU0" ;
        inject_error_i(0) <= '1';
        run(10);
        inject_error_i(0) <= '0';

        wait until (led_switch /= switch_i) ;
        wait until (led_switch  = switch_i) ;      

        report "[TESTBENCH] Inject error in CPU1" ;
        inject_error_i(1) <= '1';
        run(10);
        inject_error_i(1) <= '0';

        wait until (led_switch /= switch_i) ;
        wait until (led_switch  = switch_i) ;      

        report "[TESTBENCH] Inject error in CPU0 in continue" ;
        inject_error_i(1) <= '1';
        run(1000);
        inject_error_i(1) <= '0';

      end if;

      if (FAULT_INJECTION and SAFETY="tmr")
      then
        report "[TESTBENCH] Inject error" ;
        assert led_diff = "000" report "Bad value of led_diff" severity failure;
        
        report "[TESTBENCH] Inject error in CPU0" ;
        inject_error_i(0) <= '1';
        run(10);
        inject_error_i(0) <= '0';

        run(100);
        assert led_switch  = switch_i report "Bad value of led_switch" severity failure;
        assert led_diff    = "000"    report "Bad value of led_diff"   severity failure;

        report "[TESTBENCH] Inject error in CPU1" ;
        inject_error_i(1) <= '1';
        run(10);
        inject_error_i(1) <= '0';

        wait until (led_switch /= switch_i) ;
        wait until (led_switch  = switch_i) ;      

        assert led_switch  = switch_i report "Bad value of led_switch" severity failure;
        assert led_diff    = "001"    report "Bad value of led_diff"   severity failure;

        report "[TESTBENCH] Inject error in CPU2" ;
        inject_error_i(2) <= '1';
        run(10);
        inject_error_i(2) <= '0';

        run(100);
        assert led_switch  = switch_i report "Bad value of led_switch" severity failure;
        assert led_diff    = "001"    report "Bad value of led_diff"   severity failure;

        report "[TESTBENCH] Inject error in CPU2" ;
        inject_error_i(2) <= '1';
        run(10);
        inject_error_i(2) <= '0';

        run(100);
        assert led_switch  = switch_i report "Bad value of led_switch" severity failure;
        assert led_diff    = "001"    report "Bad value of led_diff"   severity failure;
        
        report "[TESTBENCH] Inject error in CPU1" ;
        inject_error_i(1) <= '1';
        run(10);
        inject_error_i(1) <= '0';

        wait until (led_switch /= switch_i) ;
        wait until (led_switch  = switch_i) ;      

        assert led_diff    = "010"    report "Bad value of led_diff"   severity failure;
        
        report "[TESTBENCH] Inject error in CPU0 in continue" ;
        inject_error_i(1) <= '1';
        run(1000);
        inject_error_i(1) <= '0';

        assert led_switch  = switch_i report "Bad value of led_switch" severity failure;
        assert led_diff    = "010"    report "Bad value of led_diff"   severity failure;

      end if;
        
      report "[TESTBENCH] Test OK";
      test_done <= '1';
      wait;
  end process;


end architecture tb;
