-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC
-- Project    :
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2017-03-30
-- Last update: 2026-11-20
-- Platform   :
-- Standard   : VHDL-2008
-------------------------------------------------------------------------------
-- Description: Self-checking UVVM testbench of PicoSoC_top, driven by the
--              firmware of the user ROM (generator of the target)
--              TESTS_LIST : scenarios run in sequence, separated by ','
--                           (tb_PicoSoC_tests_pkg), each one after a reset
--                           pulse ; "" : build and elaboration only
--              FIRMWARE   : program of the user ROM (identity, user,
--                           user_uart, user_uart_spi, user_uart_spi_mem,
--                           hello, test_<ip>) : selects the scenarios
--                           that apply
--              UART console : with an integration firmware, every line
--                           is logged and "FAIL <step>" is an error at once
-------------------------------------------------------------------------------
-- Copyright (c) 2017
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2017-03-30  1.0      mrosiere Created
-- 2025-01-11  1.1      mrosiere Add fault test
-- 2026-11-20  2.0      mrosiere TESTS_LIST, one package per scenario
--                               (tb_PicoSoC_<name>_pkg), helpers in
--                               tb_PicoSoC_bfm_pkg, reset pulse before each
--                               scenario, FIRMWARE replaces TEST_SUITE,
--                               TEST_IT and TEST_UART, UVVM checks
-- 2026-11-21  2.1      mrosiere UART console, integration firmwares
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_uart;
use     bitvis_vip_uart.uart_bfm_pkg.all;

library asylum;
use     asylum.PicoSoC_pkg.all;
use     asylum.spi_pkg.all;
use     asylum.string_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_tests_pkg.all;

entity tb_PicoSoC is
  generic
    (FSYS                  : positive := 50_000_000
    ;FSYS_INT              : positive := 50_000_000
    ;USER_NB_CPU           : positive := 1
    ;USER_BAUD_RATE        : integer  := 115200
    ;SUPERVISOR            : boolean  := True
    ;USER_SAFETY           : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;USER_FAULT_INJECTION  : boolean  := True
    ;DEBUG_ENABLE          : boolean  := True
    ;CPU_MODEL             : string   := ""          -- "OpenBlaze8" / "WardRV_fsm"
    ;RESET_POLARITY        : string   := "low"       -- "high" / "low"
    ;USER_IT_POLARITY      : string   := "high"      -- "high" / "low"
    ;USER_FAULT_POLARITY   : string   := "high"      -- "high" / "low"

    -- TB Parameters
    ;TESTS_LIST            : string   := ""          -- Scenarios, e.g. "switch,it_user"
    ;FIRMWARE              : string   := "user"      -- Program of the user ROM (C_FIRMWARES)
    ;TB_WATCHDOG           : natural  := 10_000      -- Timeout of one wait (clk_i cycles)
    ;SPI_MODEL             : string   := "none"      -- "none" / "m25p40" / "s25fl512s"
     );

end entity tb_PicoSoC;

architecture tb of tb_PicoSoC is
  -- =====[ Parameters ]==========================
  constant C_SCOPE                 : string  := "TB_PICOSOC";
  constant TB_PERIOD               : time    := (1e9 / FSYS) * 1 ns;

  constant USER_NB_SWITCH          : positive :=  8;
  constant USER_NB_LED0            : positive :=  8;
  constant USER_NB_LED1            : positive :=  8;
  constant USER_SPI_NB_IO          : positive :=  8;

  -- Active level of the inputs
  constant C_RESET_ON              : std_logic := active_level(RESET_POLARITY     );
  constant C_IT_ON                 : std_logic := active_level(USER_IT_POLARITY   );
  constant C_FAULT_ON              : std_logic := active_level(USER_FAULT_POLARITY);

  -- The SPI memory models are ready 10 ms after the power-up (tPUW)
  constant C_MEM_POWER_UP          : time     := 10 ms;

  -- Bit time of the DUT : the baud tick counter divides the internal clock by FSYS_INT/USER_BAUD_RATE
  constant C_UART_BIT_TIME         : time     := (FSYS_INT/USER_BAUD_RATE) * (1 sec / FSYS_INT);

  constant C_CFG                   : t_tb_cfg := (
    clk_period => TB_PERIOD,
    clk_ratio  => FSYS/FSYS_INT,
    timeout    => TB_WATCHDOG * TB_PERIOD,
    nb_cpu     => USER_NB_CPU,
    tmr        => USER_SAFETY = "tmr",
    spi_byte   => to_spi_byte(FIRMWARE),
    it_on      => C_IT_ON,
    fault_on   => C_FAULT_ON,
    uart       => (
      bit_time                              => C_UART_BIT_TIME,
      num_data_bits                         => 8,
      idle_state                            => '1',
      num_stop_bits                         => STOP_BITS_ONE,
      parity                                => PARITY_NONE,
      timeout                               => TB_WATCHDOG * TB_PERIOD,
      timeout_severity                      => error,
      num_bytes_to_log_before_expected_data => 10,
      match_strictness                      => MATCH_EXACT,
      id_for_bfm                            => ID_NEVER,
      id_for_bfm_wait                       => ID_NEVER,
      id_for_bfm_poll                       => ID_NEVER,
      id_for_bfm_poll_summary               => ID_NEVER,
      error_injection                       => C_BFM_ERROR_INJECTION_INACTIVE
      )
    );

  -- =====[ Dut Signals ]=========================
  signal  clk_i                    : std_logic := '0';
  signal  clk_ena                  : boolean   := true;
  signal  arst_i                   : std_logic := C_RESET_ON;
  signal  switch_i                 : std_logic_vector(USER_NB_SWITCH-1 downto 0) := (others => '0');
  signal  led0_o                   : std_logic_vector(USER_NB_LED0  -1 downto 0);
  signal  led1_o                   : std_logic_vector(USER_NB_LED1  -1 downto 0);
  signal  led_diff_o               : std_logic_vector(             3-1 downto 0);
  signal  it_user_i                : std_logic := not C_IT_ON;
  signal  inject_error_i           : std_logic_vector(             3-1 downto 0) := (others => not C_FAULT_ON);

  signal  spi_sclk_io              : std_logic;
  signal  spi_cs_b_io              : std_logic;
  signal  spi_io_io                : std_logic_vector(USER_SPI_NB_IO-1 downto 0);

  signal  RSTNeg                   : std_logic;
  signal  uart_tx_o                : std_logic;
  signal  uart_rx_i                : std_logic := '1';

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
    ,DEBUG_ENABLE          => DEBUG_ENABLE
    ,SUPERVISOR            => SUPERVISOR
    ,USER_SAFETY           => USER_SAFETY
    ,USER_FAULT_INJECTION  => USER_FAULT_INJECTION
    ,USER_IT_POLARITY      => USER_IT_POLARITY
    ,USER_FAULT_POLARITY   => USER_FAULT_POLARITY
    ,CPU_MODEL             => CPU_MODEL
     )
    port map
    (clk_i            => clk_i
    ,arst_i           => arst_i
    ,switch_i         => switch_i
    ,led0_o           => led0_o
    ,led1_o           => led1_o
    ,led_diff_o       => led_diff_o
    ,it_user_i        => it_user_i
    ,inject_error_i   => inject_error_i
    ,uart_tx_o        => uart_tx_o
    ,uart_rx_i        => uart_rx_i
    ,uart_cts_b_i     => '0'
    ,uart_rts_b_o     => open
    ,spi_sclk_io      => spi_sclk_io
    ,spi_cs_b_io      => spi_cs_b_io
    ,spi_io_io        => spi_io_io
    ,debug_mux_i      => "000"
    ,debug_o          => open
    ,debug_uart_tx_o  => open
    );

  -- Pull-ups of the SPI pads
  spi_sclk_io <= 'H';
  spi_cs_b_io <= 'H';
  spi_io_io   <= (others => 'H');

  -----------------------------------------------------------------------------
  -- Clock
  -----------------------------------------------------------------------------
  clock_generator(clk_i, clk_ena, TB_PERIOD, "TB Clock");

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
  -- UART console of the integration firmwares (esw/test_<ip>.c) : logs their
  -- lines (no timeout : the scenarios check what they expect) and stops on
  -- "FAIL <step>" (esw/include/test.h), whatever the scenario waits for.
  -- Other firmwares : off (a reset between two scenarios may cut a byte)
  -----------------------------------------------------------------------------
  p_console : process
    variable v_cfg     : t_tb_cfg := C_CFG;
    variable v_line    : string(1 to 128);
    variable v_len     : natural;
  begin
    if not list_contains(C_INTEGRATION, FIRMWARE)
    then
      wait;
    end if;

    v_cfg.uart.timeout := 0 ns;
    if uart_tx_o /= '1'
    then
      wait until uart_tx_o = '1'; -- idle after the reset
    end if;
    loop
      uart_get_line(v_line, v_len, uart_tx_o, v_cfg);
      log(ID_SEQUENCER_SUB, "UART : " & v_line(1 to v_len), C_SCOPE);
      if v_len >= 4 and v_line(1 to 4) = "FAIL"
      then
        alert(ERROR, "Firmware : " & v_line(1 to v_len), C_SCOPE);
      end if;
    end loop;
  end process;

  -----------------------------------------------------------------------------
  -- Sequencer
  -----------------------------------------------------------------------------
  p_sequencer : process
  begin
    log(ID_LOG_HDR, "CPU_MODEL = " & CPU_MODEL & ", USER_NB_CPU = " & integer'image(USER_NB_CPU) &
                    ", SUPERVISOR = " & boolean'image(SUPERVISOR) & ", USER_SAFETY = " & USER_SAFETY &
                    ", USER_FAULT_INJECTION = " & boolean'image(USER_FAULT_INJECTION) &
                    ", polarities (reset, it, fault) = " & RESET_POLARITY & ", " & USER_IT_POLARITY & ", " & USER_FAULT_POLARITY &
                    ", FIRMWARE = " & FIRMWARE & ", TESTS_LIST : " & TESTS_LIST, C_SCOPE);

    -- Every name is checked before the first scenario
    if not list_contains(C_FIRMWARES, FIRMWARE)
    then
      alert(TB_ERROR, "Unknown firmware """ & FIRMWARE & """ (firmwares : " & C_FIRMWARES & ")", C_SCOPE);
    end if;

    for i in 1 to list_length(TESTS_LIST) loop
      if not list_contains(C_TESTS, list_item(TESTS_LIST, i))
      then
        alert(TB_ERROR, "Unknown test """ & list_item(TESTS_LIST, i) & """ (tests : " & C_TESTS & ")", C_SCOPE);
      elsif not test_applies(list_item(TESTS_LIST, i), FIRMWARE, SUPERVISOR, USER_SAFETY, USER_FAULT_INJECTION)
      then
        alert(TB_ERROR, "Test """ & list_item(TESTS_LIST, i) & """ does not apply to the firmware " & FIRMWARE &
                        " and the configuration", C_SCOPE);
      end if;
    end loop;

    for i in 1 to list_length(TESTS_LIST) loop
      -- Inputs inactive, then reset pulse : each scenario starts from reset
      switch_i       <= (others => '0');
      it_user_i      <= not C_IT_ON;
      inject_error_i <= (others => not C_FAULT_ON);
      uart_rx_i      <= '1';
      if (SPI_MODEL /= "none") and (now < C_MEM_POWER_UP)
      then
        wait for C_MEM_POWER_UP - now;
      end if;
      do_reset(C_RESET_ON, clk_i, arst_i);

      log(ID_LOG_HDR, "TEST " & integer'image(i) & "/" & integer'image(list_length(TESTS_LIST)) & " : " & list_item(TESTS_LIST, i), C_SCOPE);
      run_test(list_item(TESTS_LIST, i), C_CFG, clk_i, switch_i, it_user_i, inject_error_i, led0_o, led1_o, led_diff_o, uart_rx_i, uart_tx_o);
    end loop;

    report_alert_counters(FINAL);
    std.env.stop;
    wait;
  end process;

end architecture tb;
