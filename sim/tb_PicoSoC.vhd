-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC.vhd
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
use     asylum.spi_pkg.all;
library work;

library uvvm_util;
context uvvm_util.uvvm_util_context;
library bitvis_vip_uart;
use     bitvis_vip_uart.uart_bfm_pkg.all;
  
entity tb_PicoSoC is
  generic
    (FSYS                  : positive := 50_000_000
    ;FSYS_INT              : positive := 50_000_000
    ;USER_NB_CPU           : positive := 1
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
    ;TEST_SUITE            : string   := "default"   -- "default"/"none" 
    ;TB_WATCHDOG           : natural  := 10_000
    ;SPI_MODEL             : string   := "none"      -- "none" / "m25p40" / "s25fl512s"
    ;TEST_IT               : boolean  := false       -- Check the user interruption (LED1 counter of esw/user.c)
    ;TEST_UART             : string   := "none"      -- Check the UART output of esw/user.c (HAVE_UART) :
                                                     -- "none" / "user" / "user_spi" (SPI loopback) / "user_spi_mem" (SPI memory)

     );
  
end entity tb_PicoSoC;

architecture tb of tb_PicoSoC is
  -- =====[ Parameters ]==========================
  constant TB_PERIOD               : time    := (1e9 / FSYS) * 1 ns;
  constant TB_WATCHDOG_TIME        : time    := TB_WATCHDOG * TB_PERIOD;

  constant USER_NB_SWITCH          : positive :=  8;
  constant USER_NB_LED0            : positive :=  8;
  constant USER_NB_LED1            : positive :=  8;
  constant USER_SPI_NB_IO          : positive :=  8;

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

  signal  spi_sclk_io              : std_logic;
  signal  spi_cs_b_io              : std_logic;
  signal  spi_io_io                : std_logic_vector(USER_SPI_NB_IO-1 downto 0);

  signal  RSTNeg                   : std_logic;
  signal  uart_tx_o                : std_logic;
  
  alias   led_switch               : std_logic_vector(USER_NB_SWITCH-1 downto 0) is led0_o(USER_NB_SWITCH-1 downto  0);
  alias   led_it                   : std_logic_vector(USER_NB_LED1  -1 downto 0) is led1_o;
  alias   led_diff                 : std_logic_vector(             3-1 downto 0) is led_diff_o;

  -- =====[ Test Signals ]========================
  signal  test_begin               : std_logic := '0';
  signal  test_done                : std_logic := '0';

  -- =====[ User Interruption ]===================
  constant C_CLK_RATIO             : positive := FSYS/FSYS_INT;           -- clk_i cycles per internal clock cycle
  constant C_IT_PULSE_SHORT        : positive :=     4*C_CLK_RATIO;       -- short pulse : one interruption
  constant C_IT_PULSE_LONG         : positive :=   100;                    -- long  pulse : at least one interruption
  constant C_IT_TIMEOUT            : positive := 20000*C_CLK_RATIO;       -- max latency of the interruption routine
  constant C_IT_SETTLE             : positive :=   500*C_CLK_RATIO;       -- LED1 must not change after the interruption

  -- =====[ UART Checker ]========================
  -- Bit time of the DUT : the baud tick counter divides the internal clock by FSYS_INT/USER_BAUD_RATE
  constant C_UART_BIT_TIME         : time     := (FSYS_INT/USER_BAUD_RATE) * (1 sec / FSYS_INT);
  constant C_UART_MIN_LOOP         : positive := 2;                        -- Minimum number of "Loop" lines
  constant C_UART_BFM_CONFIG       : t_uart_bfm_config := (
    bit_time                              => C_UART_BIT_TIME,
    num_data_bits                         => 8,
    idle_state                            => '1',
    num_stop_bits                         => STOP_BITS_ONE,
    parity                                => PARITY_NONE,
    timeout                               => 0 ns,
    timeout_severity                      => error,
    num_bytes_to_log_before_expected_data => 10,
    match_strictness                      => MATCH_EXACT,
    id_for_bfm                            => ID_NEVER,
    id_for_bfm_wait                       => ID_NEVER,
    id_for_bfm_poll                       => ID_NEVER,
    id_for_bfm_poll_summary               => ID_NEVER,
    error_injection                       => C_BFM_ERROR_INJECTION_INACTIVE
    );
  signal  uart_check_end           : std_logic := '0';
  signal  uart_check_done          : std_logic := '0';
  
  -- =====[ Functions ]===========================
  
  -----------------------------------------------------------------------------
  -- xrun
  -----------------------------------------------------------------------------
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

  -----------------------------------------------------------------------------
  -- run
  -----------------------------------------------------------------------------
  procedure run
    (constant n     : in positive;          -- nb cycle
     constant pol   : in string := "pos"
     ) is
    
  begin
    xrun(n,"pos",clk_i);
  end run;

begin  -- architecture tb

  -----------------------------------------------------------------------------
  -- Design Under Test
  -----------------------------------------------------------------------------
  dut : PicoSoC_top
    generic map
    (FSYS                  => FSYS            
    ,FSYS_INT              => FSYS_INT        
    ,USER_NB_CPU           => USER_NB_CPU
    ,USER_BAUD_RATE        => USER_BAUD_RATE
    ,USER_NB_SWITCH        => USER_NB_SWITCH       
    ,USER_NB_LED0          => USER_NB_LED0        
    ,USER_NB_LED1          => USER_NB_LED1   
    ,USER_SPI_NB_IO        => USER_SPI_NB_IO     
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
    ,uart_tx_o        => uart_tx_o
    ,uart_rx_i        => '1'
    ,uart_cts_b_i     => '0'
    ,uart_rts_b_o     => open
    ,spi_sclk_io      => spi_sclk_io
    ,spi_cs_b_io      => spi_cs_b_io
    ,spi_io_io        => spi_io_io
    ,debug_mux_i      => "000"
    ,debug_o          => open 
    ,debug_uart_tx_o  => open
    );

  -----------------------------------------------------------------------------
  -- Clock Tree
  -----------------------------------------------------------------------------
  clk_i <= not test_done and not clk_i after TB_PERIOD/2;

  -----------------------------------------------------------------------------
  -- Memory Model
  -----------------------------------------------------------------------------
  RSTNeg  <= '1';

  gen_m25p40:
  if SPI_MODEL = "m25p40" 
  generate
    mem : entity work.m25p40(vhdl_behavioral)
      generic map 
      (mem_file_name  => "memory.mem"
      ,UserPreload    => true
      ,DebugInfo      => true
      ,TimingChecksOn => true
      ,MsgOn          => true
      ,XOn            => true
      ,LongTimming    => False
      )
      port map
      (D             => spi_io_io(SPI_IO_MOSI)
      ,Q             => spi_io_io(SPI_IO_MISO)
      ,C             => spi_sclk_io
      ,SNeg          => spi_cs_b_io
      ,WNeg          => spi_io_io(SPI_IO_WP_B)
      ,HOLDNeg       => spi_io_io(SPI_IO_HOLD_B)
      );
  end generate;

  gen_s25fl512s:
  if SPI_MODEL = "s25fl512s" 
  generate
    mem : entity work.s25fl512s(vhdl_behavioral_static_memory_allocation)
      generic map
      (mem_file_name  => "memory.mem"
      ,otp_file_name  => "none"
      ,UserPreload    => true
      ,TimingChecksOn => true
      ,MsgOn          => true
      ,XOn            => true
      ,TimingModel    => "S25FL512SAGMFI010_F_30pF"
      ,LongTimming    => false
      )
      PORT MAP
      (SI            => spi_io_io(SPI_IO_MOSI)
      ,SO            => spi_io_io(SPI_IO_MISO)
      ,SCK           => spi_sclk_io
      ,CSNeg         => spi_cs_b_io
      ,WPNeg         => spi_io_io(SPI_IO_WP_B)
      ,HOLDNeg       => spi_io_io(SPI_IO_HOLD_B)
      ,RSTNeg        => RSTNeg
      );
  end generate;
  
  -----------------------------------------------------------------------------
  -- UART Checker (esw/user.c with HAVE_UART)
  -- * "Welcome Back, Commander" after each reset of the user SoC
  -- * then one line per loop iteration while switch(5) is set :
  --   "Loop CCCCCCCC-SS-PP Lock 00 FF MB0 00 01 02 03 04 05 06 07 "
  --   CCCCCCCC : loop counter, SS : switches (bit 5 set),
  --   PP       : SPI byte (00 without SPI, CC(7:0) with the SPI loopback,
  --              byte CCCCCCCC of memory.mem with the SPI memory)
  -- The check stops when uart_check_end is set
  -----------------------------------------------------------------------------
  gen_uart_check: if TEST_UART /= "none"
  generate
    p_uart_check: process is
      constant C_BANNER     : string  := "Welcome Back, Commander";
      variable v_byte       : std_logic_vector(8-1 downto 0);
      variable v_line       : string(1 to 128);
      variable v_len        : natural;
      variable v_cpt        : natural := 0; -- expected loop counter
      variable v_nb_banner  : natural := 0;
      variable v_nb_loop    : natural := 0;
      variable v_spi        : std_logic_vector(8-1 downto 0);
      variable v_sw         : std_logic_vector(8-1 downto 0);

      function hex (value : natural; width : positive) return string is
      begin
        return to_hstring(std_logic_vector(to_unsigned(value,4*width)));
      end function hex;

      impure function hex2slv (str : string) return std_logic_vector is
        variable v_res : std_logic_vector(4*str'length-1 downto 0);
        variable v_dig : natural;
      begin
        for i in 0 to str'length-1 loop
          case str(str'left+i) is
            when '0' to '9' => v_dig := character'pos(str(str'left+i)) - character'pos('0');
            when 'A' to 'F' => v_dig := character'pos(str(str'left+i)) - character'pos('A') + 10;
            when others     => v_dig := 0;
                               assert false report "[TESTBENCH] UART : bad hexadecimal digit in "&str severity failure;
          end case;
          v_res(v_res'left-4*i downto v_res'left-4*i-3) := std_logic_vector(to_unsigned(v_dig,4));
        end loop;
        return v_res;
      end function hex2slv;
    begin
      set_alert_stop_limit(ERROR,1);

      wait until test_begin = '1';
      if uart_tx_o /= '1'
      then
        wait until uart_tx_o = '1';
      end if;

      while uart_check_end = '0'
      loop
        -- Receive one line
        v_len := 0;
        loop
          uart_receive(v_byte, "UART TX", uart_tx_o, uart_check_end, C_UART_BFM_CONFIG);
          exit when uart_check_end = '1' or v_byte = x"0A";
          assert v_len < v_line'length report "[TESTBENCH] UART : line too long : "&v_line severity failure;
          if v_byte /= x"0D"
          then
            v_len         := v_len+1;
            v_line(v_len) := character'val(to_integer(unsigned(v_byte)));
          end if;
        end loop;
        exit when uart_check_end = '1';

        report "[TESTBENCH] UART : "&v_line(1 to v_len);

        if v_line(1 to v_len) = C_BANNER
        then
          -- (re)start of the firmware
          v_cpt       := 0;
          v_nb_banner := v_nb_banner+1;
        else
          assert v_nb_banner > 0 and v_len >= 16 and v_line(1 to 5) = "Loop "
            report "[TESTBENCH] UART : unexpected line : "&v_line(1 to v_len) severity failure;

          v_sw := hex2slv(v_line(15 to 16));
          assert v_sw(5) = '1'
            report "[TESTBENCH] UART : switch(5) not set in "&v_line(1 to v_len) severity failure;

          if    TEST_UART = "user_spi"     then v_spi := std_logic_vector(to_unsigned(v_cpt mod 256,8));
          elsif TEST_UART = "user_spi_mem" then v_spi := std_logic_vector(to_unsigned(v_cpt+1,8)) when v_cpt < 15 else x"FF";
          else                                  v_spi := x"00";
          end if;

          assert v_line(1 to v_len) = "Loop "&hex(v_cpt,8)&"-"&v_line(15 to 16)&"-"&to_hstring(v_spi)&
                                      " Lock 00 FF MB0 00 01 02 03 04 05 06 07 "
            report "[TESTBENCH] UART : bad line : "&v_line(1 to v_len)&" (loop "&integer'image(v_cpt)&")" severity failure;

          v_cpt     := v_cpt    +1;
          v_nb_loop := v_nb_loop+1;
        end if;
      end loop;

      assert v_nb_banner > 0 and v_nb_loop >= C_UART_MIN_LOOP
        report "[TESTBENCH] UART : "&integer'image(v_nb_banner)&" banner and "&integer'image(v_nb_loop)&" loop lines received" severity failure;

      report "[TESTBENCH] UART : "&integer'image(v_nb_loop)&" loop lines checked";
      uart_check_done <= '1';
      wait;
    end process p_uart_check;
  end generate gen_uart_check;

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

    run(1);
    
    assert (test_done = '1') report "[TESTBENCH] Test KO : Maximum cycle is reached" severity failure;

    -- end of process
    wait;
  end process;
  
  -----------------------------------------------------------------------------
  -- Test suite
  -----------------------------------------------------------------------------
  process is
    variable v_led_it : unsigned(USER_NB_LED1-1 downto 0);
    variable v_cycle  : natural;
  begin  -- process

      run(10);

      report "[TESTBENCH] Init signals";
      it_user_i      <= '0';             -- active low
      inject_error_i <= (others => '0'); -- active low

      report "[TESTBENCH] Reset Sequence"; 
      arst_b_i       <= '0';

      if SPI_MODEL /= "none"
      then
        wait for 10 ms;
      end if;
      
      run(1);

      test_begin     <= '1';
      arst_b_i       <= '1';

      -------------------------------------------------------------------------
      if TEST_SUITE = "default"
      -------------------------------------------------------------------------
      then
      
        report "[TESTBENCH] Change Switch" ;
        switch_i       <= (others => '0');
        for i in USER_NB_SWITCH-1 downto 0 loop
          report "[TESTBENCH]   Switch " & integer'image(i);
          switch_i(i)    <= '1';
          wait until (led_switch = switch_i) ;
          
        end loop;  -- i
  
        -- esw/user.c increments LED1 in the interruption routine of it_user_i
        -- * short pulses : exactly one interruption each
        -- * long  pulse  : at least one interruption (the GIC input is level sensitive)
        report "[TESTBENCH] User Interruption" ;
        for i in 0 to 2
        loop
          v_led_it         := unsigned(led_it);
          run(1,"neg");
          it_user_i        <= '1';
          if i < 2
          then
            run(C_IT_PULSE_SHORT);
          else
            run(C_IT_PULSE_LONG);
          end if;
          run(1,"neg");
          it_user_i        <= '0';

          if TEST_IT
          then
            v_cycle := 0;
            while (unsigned(led_it) = v_led_it) and (v_cycle < C_IT_TIMEOUT)
            loop
              run(1);
              v_cycle := v_cycle+1;
            end loop;
            run(C_IT_SETTLE);

            if i < 2
            then
              assert unsigned(led_it) = v_led_it+1
                report "[TESTBENCH] User Interruption (short pulse) : LED1 = "&to_hstring(led_it)&", expected "&to_hstring(v_led_it+1)
                severity failure;
            else
              assert unsigned(led_it) > v_led_it
                report "[TESTBENCH] User Interruption (long pulse) : LED1 = "&to_hstring(led_it)&", expected > "&to_hstring(v_led_it)
                severity failure;
            end if;

            -- No other interruption
            v_led_it := unsigned(led_it);
            run(C_IT_SETTLE);
            assert unsigned(led_it) = v_led_it
              report "[TESTBENCH] User Interruption : LED1 changed without interruption"
              severity failure;
          else
            run(1000);
          end if;
        end loop;

        if TEST_UART /= "none"
        then
          report "[TESTBENCH] End of the UART check";
          uart_check_end <= '1';
          wait until uart_check_done = '1' for 1 ms;
          assert uart_check_done = '1' report "[TESTBENCH] UART check not done" severity failure;
        end if;

        if (USER_FAULT_INJECTION and SUPERVISOR and USER_SAFETY="lock-step")
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
          inject_error_i(0) <= '1';
          run(100);
          inject_error_i(0) <= '0';
  
          -- The supervisor resets the user SoC, then the firmware copies again the switches into LED0
          v_cycle := 0;
          while (not (led_switch /= switch_i)) and (v_cycle < TB_WATCHDOG)
          loop
            run(1);
            v_cycle := v_cycle+1;
          end loop;
          assert led_switch /= switch_i report "[TESTBENCH] No reset of the user SoC after the error in CPU0" severity failure;
          v_cycle := 0;
          while (not (led_switch  = switch_i)) and (v_cycle < TB_WATCHDOG)
          loop
            run(1);
            v_cycle := v_cycle+1;
          end loop;
          assert led_switch  = switch_i report "[TESTBENCH] Bad value of led_switch after the reset of the user SoC" severity failure;

        end if;
  
        if (USER_FAULT_INJECTION and SUPERVISOR and USER_SAFETY="tmr")
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
      end if;
        
      -------------------------------------------------------------------------
      if TEST_SUITE = "none"
      -------------------------------------------------------------------------
      then
        -- just run
        wait for TB_WATCHDOG_TIME;

      end if;

      report "[TESTBENCH] Test OK";
      test_done <= '1';
      wait;
  end process;


end architecture tb;
