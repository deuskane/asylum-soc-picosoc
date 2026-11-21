-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_modbus_rtu
-- Project    :
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_modbus_rtu.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2025-10-23
-- Last update: 2026-11-20
-- Platform   :
-- Standard   : VHDL-2008
-------------------------------------------------------------------------------
-- Description: Self-checking UVVM testbench of PicoSoC_top with the firmware
--              esw/user_modbus_rtu.c : a Modbus RTU master on the UART reads
--              and writes the SoC addresses
--              TESTS_LIST : scenarios run in sequence, separated by ','
--                           (tb_PicoSoC_modbus_rtu_tests_pkg), each one
--                           after a reset pulse ; "" : build and
--                           elaboration only
-------------------------------------------------------------------------------
-- Copyright (c) 2025
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2025-10-23  1.0      mrosiere Created
-- 2026-11-20  2.0      mrosiere TESTS_LIST, one package per scenario
--                               (tb_PicoSoC_modbus_rtu_<name>_pkg), helpers
--                               in tb_PicoSoC_modbus_rtu_bfm_pkg, reset pulse
--                               before each scenario
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
use     asylum.string_pkg.all;

library work;
use     work.tb_PicoSoC_modbus_rtu_bfm_pkg.all;
use     work.tb_PicoSoC_modbus_rtu_tests_pkg.all;

entity tb_PicoSoC_modbus_rtu is
  generic
    (FSYS                  : positive := 50_000_000
    ;FSYS_INT              : positive := 50_000_000
    ;USER_BAUD_RATE        : integer  := 115200
    ;USER_UART_DEPTH_TX    : natural  := 8
    ;USER_UART_DEPTH_RX    : natural  := 8
    ;SUPERVISOR            : boolean  := True
    ;USER_SAFETY           : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;USER_FAULT_INJECTION  : boolean  := True
    ;DEBUG_ENABLE          : boolean  := True
    ;CPU_MODEL             : string   := ""          -- "OpenBlaze8" / "WardRV_fsm"
    ;RESET_POLARITY        : string   := "low"       -- "high" / "low"
    ;USER_IT_POLARITY      : string   := "high"      -- "high" / "low"
    ;USER_FAULT_POLARITY   : string   := "high"      -- "high" / "low"

    -- TB Parameters
    ;TESTS_LIST            : string   := ""          -- Scenarios, e.g. "basic,sequence"
     );

end entity tb_PicoSoC_modbus_rtu;

architecture tb of tb_PicoSoC_modbus_rtu is

  -- =====[ Parameters ]==========================
  constant C_SCOPE                 : string   := "TB_MODBUS";

  constant USER_NB_SWITCH          : positive :=  8;
  constant USER_NB_LED0            : positive :=  8;
  constant USER_NB_LED1            : positive :=  8;

  -- Active level of the inputs
  constant C_RESET_ON              : std_logic := active_level(RESET_POLARITY     );
  constant C_IT_ON                 : std_logic := active_level(USER_IT_POLARITY   );
  constant C_FAULT_ON              : std_logic := active_level(USER_FAULT_POLARITY);

  constant C_CLK_PERIOD            : time     := 1 sec / FSYS;

  constant C_CFG                   : t_tb_cfg := (
    clk_period => C_CLK_PERIOD,
    fault_on   => C_FAULT_ON,
    uart       => (
      -- Bit time of the DUT : the baud tick counter divides the internal clock by FSYS_INT/USER_BAUD_RATE
      bit_time                              => (FSYS_INT/USER_BAUD_RATE) * (1 sec / FSYS_INT),
      num_data_bits                         => 8,
      idle_state                            => '1',
      num_stop_bits                         => STOP_BITS_ONE,
      parity                                => PARITY_NONE,
      timeout                               => 0 ns, -- will default never time out
      timeout_severity                      => error,
      num_bytes_to_log_before_expected_data => 10,
      match_strictness                      => MATCH_EXACT,
      id_for_bfm                            => ID_BFM,
      id_for_bfm_wait                       => ID_BFM_WAIT,
      id_for_bfm_poll                       => ID_BFM_POLL,
      id_for_bfm_poll_summary               => ID_BFM_POLL_SUMMARY,
      error_injection                       => C_BFM_ERROR_INJECTION_INACTIVE
      )
    );

  -- =====[ Dut Signals ]=========================
  signal   clk_i                   : std_logic := '0';
  signal   clk_ena                 : boolean   := false;
  signal   arst_i                  : std_logic := not C_RESET_ON;
  signal   switch_i                : std_logic_vector(USER_NB_SWITCH-1 downto 0) := (others => '0');
  signal   led0_o                  : std_logic_vector(USER_NB_LED0  -1 downto 0);
  signal   led1_o                  : std_logic_vector(USER_NB_LED1  -1 downto 0);
  signal   led_diff_o              : std_logic_vector(             3-1 downto 0);
  signal   it_user_i               : std_logic := not C_IT_ON;
  signal   inject_error_i          : std_logic_vector(             3-1 downto 0) := (others => not C_FAULT_ON);
  signal   uart_tx_o               : std_logic;
  signal   uart_rx_i               : std_logic := '1';

begin  -- architecture tb

  -----------------------------------------------------------------------------
  -- Design Under Test
  -----------------------------------------------------------------------------
  dut : PicoSoC_top
    generic map
    (FSYS                  => FSYS
    ,FSYS_INT              => FSYS_INT
    ,USER_BAUD_RATE        => USER_BAUD_RATE
    ,USER_NB_SWITCH        => USER_NB_SWITCH
    ,USER_NB_LED0          => USER_NB_LED0
    ,USER_NB_LED1          => USER_NB_LED1
    ,RESET_POLARITY        => RESET_POLARITY
    ,DEBUG_ENABLE          => DEBUG_ENABLE
    ,SUPERVISOR            => SUPERVISOR
    ,USER_SAFETY           => USER_SAFETY
    ,USER_FAULT_INJECTION  => USER_FAULT_INJECTION
    ,USER_IT_POLARITY      => USER_IT_POLARITY
    ,USER_FAULT_POLARITY   => USER_FAULT_POLARITY
    ,USER_UART_DEPTH_TX    => USER_UART_DEPTH_TX
    ,USER_UART_DEPTH_RX    => USER_UART_DEPTH_RX
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
    ,spi_sclk_io      => open
    ,spi_cs_b_io      => open
    ,spi_io_io        => open
    ,i2c_scl_io       => open
    ,i2c_sda_io       => open
    ,debug_uart_tx_o  => open
    );

  -----------------------------------------------------------------------------
  -- Clock Generator
  -----------------------------------------------------------------------------
  clock_generator(clk_i, clk_ena, C_CLK_PERIOD, "TB Clock", 50);

  -----------------------------------------------------------------------------
  -- Sequencer
  -----------------------------------------------------------------------------
  p_sequencer : process
  begin
    log(ID_LOG_HDR, "CPU_MODEL = " & CPU_MODEL & ", SUPERVISOR = " & boolean'image(SUPERVISOR) &
                    ", USER_SAFETY = " & USER_SAFETY & ", USER_FAULT_INJECTION = " & boolean'image(USER_FAULT_INJECTION) &
                    ", polarities (reset, it, fault) = " & RESET_POLARITY & ", " & USER_IT_POLARITY & ", " & USER_FAULT_POLARITY &
                    ", TESTS_LIST : " & TESTS_LIST, C_SCOPE);

    -- Every name is checked before the first scenario
    for i in 1 to list_length(TESTS_LIST) loop
      if not list_contains(C_TESTS, list_item(TESTS_LIST, i))
      then
        alert(TB_ERROR, "Unknown test """ & list_item(TESTS_LIST, i) & """ (tests : " & C_TESTS & ")", C_SCOPE);
      elsif not test_applies(list_item(TESTS_LIST, i), SUPERVISOR, USER_SAFETY, USER_FAULT_INJECTION)
      then
        alert(TB_ERROR, "Test """ & list_item(TESTS_LIST, i) & """ does not apply to the configuration", C_SCOPE);
      end if;
    end loop;

    clk_ena <= true;

    for i in 1 to list_length(TESTS_LIST) loop
      -- Inputs inactive, then reset pulse : each scenario starts from reset
      switch_i       <= (others => '0');
      it_user_i      <= not C_IT_ON;
      inject_error_i <= (others => not C_FAULT_ON);
      uart_rx_i      <= '1';
      wait until falling_edge(clk_i);
      gen_pulse(arst_i, C_RESET_ON, 10 * C_CLK_PERIOD, "Reset pulse (10 cycles)");
      wait for C_RESET_LATENCY;

      log(ID_LOG_HDR, "TEST " & integer'image(i) & "/" & integer'image(list_length(TESTS_LIST)) & " : " & list_item(TESTS_LIST, i), C_SCOPE);
      run_test(list_item(TESTS_LIST, i), C_CFG, uart_rx_i, uart_tx_o, switch_i, inject_error_i, led0_o, led_diff_o);
    end loop;

    report_alert_counters(FINAL);
    std.env.stop;
    wait;
  end process p_sequencer;

end architecture tb;
