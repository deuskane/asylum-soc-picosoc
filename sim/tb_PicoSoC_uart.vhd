-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_uart
-- Project    : 
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_uart.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2025-10-23
-- Last update: 2025-10-23
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2025
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2025-10-23  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     std.textio.all;
library asylum;
use     asylum.PicoSoC_pkg.all;
library work;

library uvvm_util;
context uvvm_util.uvvm_util_context;
use     uvvm_util.uart_bfm_pkg.all;

entity tb_PicoSoC_uart is
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

end entity tb_PicoSoC_uart;

architecture tb of tb_PicoSoC_uart is

  -- =====[ Parameters ]==========================
  constant TB_PERIOD               : time    := (1e9 / FSYS) * 1 ns;
  constant TB_WATCHDOG_TIME        : time    := TB_WATCHDOG * TB_PERIOD;

  constant NB_SWITCH               : positive :=  8;
  constant NB_LED                  : positive := 19;

  constant RESET_POLARITY          : string   := "low";  -- "high" / "low"
  constant IT_USER_POLARITY        : string   := "high"; -- "high" / "low"
  constant FAULT_POLARITY          : string   := "high"; -- "high" / "low"

  -- =====[ Dut Signals ]=========================
  signal   clk_i                   : std_logic := '0';
  signal   arst_b_i                : std_logic := '1';
  signal   switch_i                : std_logic_vector(NB_SWITCH-1 downto 0);
  signal   led_o                   : std_logic_vector(NB_LED   -1 downto 0);
  signal   it_user_i               : std_logic;
  signal   inject_error_i          : std_logic_vector(        3-1 downto 0);
  signal   uart_tx_o               : std_logic;
  signal   uart_rx_i               : std_logic := '1';
           
  signal   cke                     : boolean   := false;

  constant C_CLK_PERIOD            : time      := 1 sec / FSYS;
  constant C_UART_BIT_TIME         : time      := 1 sec / BAUD_RATE;
  
  constant C_UART_BFM_CONFIG       : t_uart_bfm_config := (
    bit_time                              => C_UART_BIT_TIME,
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
    );

  constant C_MODBUS_SLAVE_ID       : std_logic_vector(8-1 downto 0) := x"01";
  constant C_MODBUS_READ           : std_logic_vector(8-1 downto 0) := x"03";
  constant C_MODBUS_WRITE          : std_logic_vector(8-1 downto 0) := x"06";

  constant C_LED0_BA               : std_logic_vector(8-1 downto 0) := x"20";
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
    ,uart_tx_o        => uart_tx_o
    ,uart_rx_i        => uart_rx_i
    ,uart_cts_b_i     => '0'
    ,uart_rts_b_o     => open
    ,spi_sclk_o       => open
    ,spi_cs_b_o       => open
    ,spi_mosi_o       => open
    ,spi_miso_i       => '0'
    ,debug_mux_i      => "000"
    ,debug_o          => open 
    ,debug_uart_tx_o  => open
    );

  
  -----------------------------------------------------------------------------
  -- Clock Generator
  -----------------------------------------------------------------------------
  clock_generator(clk_i, cke, C_CLK_PERIOD, "TB Clock", 50);

  ------------------------------------------------
  -- PROCESS: p_main
  ------------------------------------------------
  p_main: process
    constant C_SCOPE     : string  := C_TB_SCOPE_DEFAULT;

--    -- Overloads for PIF BFMs for SBI (Simple Bus Interface)
--    procedure write(
--      constant addr_value   : in natural;
--      constant data_value   : in std_logic_vector;
--      constant msg          : in string) is
--    begin
--      sbi_write(to_unsigned(addr_value, sbi_if.addr'length), data_value, msg,
--                clk, sbi_if, C_SCOPE);
--    end;
--
--    procedure check(
--      constant addr_value   : in natural;
--      constant data_exp     : in std_logic_vector;
--      constant alert_level  : in t_alert_level;
--      constant msg          : in string) is
--    begin
--      sbi_check(to_unsigned(addr_value, sbi_if.addr'length), data_exp, msg,
--                clk, sbi_if, alert_level, C_SCOPE);
--    end;

    procedure set_inputs_passive(
      dummy   : t_void) is
    begin

      switch_i        <= (others => '0');
      it_user_i       <= '0';
      inject_error_i  <= (others => '0');

      log(ID_SEQUENCER_SUB, "All inputs set passive", C_SCOPE);
    end;

  begin

    -- Print the configuration to the log
    report_global_ctrl (VOID);
    report_msg_id_panel(VOID);

    enable_log_msg     (ALL_MESSAGES);
    --disable_log_msg(ALL_MESSAGES);
    --enable_log_msg(ID_LOG_HDR);

    log(ID_LOG_HDR, "Start Simulation of TB for IRQC", C_SCOPE);
    ------------------------------------------------------------

    set_inputs_passive (VOID);

    cke <= true; -- to start clock generator

    gen_pulse(arst_b_i, '0', 10 * C_CLK_PERIOD, "Pulsed reset-signal - active for 10T");

    log(ID_LOG_HDR, "wait 100 cycles to finish init", C_SCOPE);
    wait for 100*C_CLK_PERIOD;


    uart_transmit(C_MODBUS_SLAVE_ID,"MODBUS Slave ID"             ,uart_rx_i,C_UART_BFM_CONFIG);
    uart_transmit(C_MODBUS_WRITE,   "MODBUS Write"                ,uart_rx_i,C_UART_BFM_CONFIG);
    uart_transmit(x"00",            "MODBUS Addr MSB (Ignored)"   ,uart_rx_i,C_UART_BFM_CONFIG);
    uart_transmit(C_LED0_BA,        "MODBUS Addr LSB (LED)"       ,uart_rx_i,C_UART_BFM_CONFIG);
    uart_transmit(x"00",            "MODBUS Data MSB (Ignored)"   ,uart_rx_i,C_UART_BFM_CONFIG);
    uart_transmit(x"01",            "MODBUS Data LSB (0x01)"      ,uart_rx_i,C_UART_BFM_CONFIG);
    

    --==================================================================================================
    -- Ending the simulation
    --------------------------------------------------------------------------------------
    wait for TB_WATCHDOG*C_CLK_PERIOD; -- to allow some time for completion
    report_alert_counters(FINAL);      -- Report final counters and print conclusion for simulation (Success/Fail)
    log(ID_LOG_HDR, "SIMULATION COMPLETED", C_SCOPE);

    -- Finish the simulation
    std.env.stop;
    wait;  -- to stop completely

  end process p_main;

  
end architecture tb;
