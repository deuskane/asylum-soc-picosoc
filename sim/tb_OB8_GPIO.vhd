-------------------------------------------------------------------------------
-- Title      : tb_OB8_GPIO
-- Project    : 
-------------------------------------------------------------------------------
-- File       : tb_OB8_GPIO.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2025-01-14
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

entity tb_OB8_GPIO is
  generic (
    FSYS             : positive := 50_000_000;
    FSYS_INT         : positive := 50_000_000;
    NB_SWITCH        : positive := 8;
    NB_LED           : positive := 19;
    RESET_POLARITY   : string   := "low";       -- "high" / "low"
    SUPERVISOR       : boolean  := True ;
    SAFETY           : string   := "lock-step"; -- "none" / "lock-step" / "tmr"
    FAULT_INJECTION  : boolean  := True ; 
    IT_USER_POLARITY : string   := "low";       -- "high" / "low"
    FAULT_POLARITY   : string   := "low"        -- "high" / "low"

    );
  
end entity tb_OB8_GPIO;

architecture tb of tb_OB8_GPIO is
  -- =====[ Parameters ]==========================
  constant TB_PERIOD               : time    := 10 ns;
  constant TB_DURATION             : natural := 10000;

  -- =====[ Signals ]=============================
  signal clk_i          : std_logic := '0';
  signal arstn_i        : std_logic;
  signal switch_i       : std_logic_vector(NB_SWITCH-1 downto 0);
  signal led_o          : std_logic_vector(NB_LED   -1 downto 0);
  signal it_user_i      : std_logic;
  signal inject_error_i : std_logic_vector(3-1 downto 0);

  alias led_switch : std_logic_vector(NB_SWITCH-1 downto 0) is led_o(NB_SWITCH-1 downto  0);
  alias led_it     : std_logic_vector(        8-1 downto 0) is led_o(       16-1 downto  8);
  alias led_diff   : std_logic_vector(        3-1 downto 0) is led_o(       19-1 downto 16);
  
  -------------------------------------------------------
  -- run
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

  procedure run
    (constant n     : in positive           -- nb cycle
     ) is
    
  begin
    xrun(n,"pos",clk_i);
  end run;

  -----------------------------------------------------
  -- Test signals
  -----------------------------------------------------
  signal test_done  : std_logic := '0';
  signal test_ok    : std_logic := '0';

begin  -- architecture tb

  dut : entity work.OB8_GPIO_top(rtl)
  generic map (
    FSYS             => FSYS            ,
    FSYS_INT         => FSYS_INT        ,
    NB_SWITCH        => NB_SWITCH       ,
    NB_LED           => NB_LED          ,
    RESET_POLARITY   => RESET_POLARITY  ,
    SUPERVISOR       => SUPERVISOR      ,
    SAFETY           => SAFETY          ,
    FAULT_INJECTION  => FAULT_INJECTION ,
    IT_USER_POLARITY => IT_USER_POLARITY,
    FAULT_POLARITY   => FAULT_POLARITY  
    )  
  port map(
    clk_i          => clk_i         ,
    arst_i         => arstn_i       ,
    switch_i       => switch_i      ,
    led_o          => led_o         ,
    it_user_i      => it_user_i     ,
    inject_error_i => inject_error_i
    );

  clk_i <= not test_done and not clk_i after TB_PERIOD/2;

  process is
  begin  -- process

      run(10);

      report "[TESTBENCH] Init signals";
      it_user_i      <= '1';             -- active low
      inject_error_i <= (others => '1'); -- active low

      report "[TESTBENCH] Reset Sequence"; 
      arstn_i <= '0';
      run(1);
      arstn_i <= '1';
      
      report "[TESTBENCH] Change Switch" ;
      for i in 0 to NB_SWITCH-1 loop
        switch_i    <= (others => '0');
        switch_i(i) <= '1';
        wait until (led_switch = switch_i) ;
        
      end loop;  -- i

      report "[TESTBENCH] User Interruption" ;
      xrun(1,"neg",clk_i);
      it_user_i        <= '0';
      xrun(1,"neg",clk_i);
      it_user_i        <= '1';
      run(1000);

      xrun(1,"neg",clk_i);
      it_user_i        <= '0';
      run(100);
      xrun(1,"neg",clk_i);
      it_user_i        <= '1';
      it_user_i        <= '1';
      run(1000);
      
      report "[TESTBENCH] Inject error in CPU0" ;
      inject_error_i(0) <= '0';
      run(2);
      inject_error_i(0) <= '1';

      wait until (led_switch /= switch_i) ;
      wait until (led_switch  = switch_i) ;      

      report "[TESTBENCH] Inject error in CPU1" ;
      inject_error_i(1) <= '0';
      run(2);
      inject_error_i(1) <= '1';

      wait until (led_switch /= switch_i) ;
      wait until (led_switch  = switch_i) ;      

      report "[TESTBENCH] Inject error in CPU0 in continue" ;
      inject_error_i(1) <= '0';
      run(1000);
      
      report "[TESTBENCH] Test OK";
      test_done <= '1';
      wait;
  end process;
    

  -----------------------------------------------------------------------------
  -- Testbench Limit
  -----------------------------------------------------------------------------
  l_tb_limit: process is
  begin  -- process l_tb_limit
    run(TB_DURATION);

    assert (test_done = '1') report "[TESTBENCH] Test KO : Maximum cycle is reached" severity failure;

    -- end of process
    wait;
  end process l_tb_limit;
  

end architecture tb;
