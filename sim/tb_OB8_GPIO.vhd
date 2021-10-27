-------------------------------------------------------------------------------
-- Title      : tb_OB8_GPIO
-- Project    : 
-------------------------------------------------------------------------------
-- File       : tb_OB8_GPIO.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2021-09-03
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

entity tb_OB8_GPIO is
  
end entity tb_OB8_GPIO;

architecture tb of tb_OB8_GPIO is
  -- =====[ Parameters ]==========================
  constant TB_PERIOD               : time    := 10 ns;
  constant TB_DURATION             : natural := 10000;

  -- =====[ Signals ]=============================
  signal clk_i      : std_logic := '0';
  signal arstn_i    : std_logic;
  signal switch_i   : std_logic_vector(7 downto 0);
  signal led_o      : std_logic_vector(7 downto 0);

  -------------------------------------------------------
  -- run
  -------------------------------------------------------
  procedure xrun
    (constant n     : in positive;           -- nb cycle
     signal   clk_i : in std_logic
     ) is
    
  begin
    for i in 0 to n-1
    loop
      wait until rising_edge(clk_i);        
    end loop;  -- i
  end xrun;

  procedure run
    (constant n     : in positive           -- nb cycle
     ) is
    
  begin
    xrun(n,clk_i);
  end run;

  -----------------------------------------------------
  -- Test signals
  -----------------------------------------------------
  signal test_done  : std_logic := '0';
  signal test_ok    : std_logic := '0';
    
begin  -- architecture tb

  dut : entity work.OB8_GPIO(rtl)
  port map(
    clk_i      => clk_i   ,
    arstn_i    => arstn_i ,
    switch_i   => switch_i,
    led_o      => led_o   
    );

  clk_i <= not test_done and not clk_i after TB_PERIOD/2;

  process is
  begin  -- process

      arstn_i <= '0';
        
      run(1);

      arstn_i <= '1';

      switch_i <= "01010110";
      wait until (led_o = switch_i) ;

      for i in 0 to 7 loop
        switch_i    <= (others => '0');
        switch_i(i) <= '1';
        wait until (led_o = switch_i) ;
      end loop;  -- i

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
