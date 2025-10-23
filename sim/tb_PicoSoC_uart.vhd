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



  signal   clk          : std_logic;
  signal   arst         : std_logic;
  signal   cke          : boolean   := false;

  constant C_CLK_PERIOD : time      := 1000 ms / FSYS;
  
begin  -- architecture tb

  -----------------------------------------------------------------------------
  -- Clock Generator
  -----------------------------------------------------------------------------
  clock_generator(clk, cke, C_CLK_PERIOD, "TB Clock", 50);

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
      --sbi_if.cs             <= '0';
      --sbi_if.addr           <= (others => '0');
      --sbi_if.wena           <= '0';
      --sbi_if.rena           <= '0';
      --sbi_if.wdata          <= (others => '0');
      --irq_source            <= (others => '0');
      --irq2cpu_ack            <= '0';
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

    gen_pulse(arst, 10 * C_CLK_PERIOD, "Pulsed reset-signal - active for 10T");


    --==================================================================================================
    -- Ending the simulation
    --------------------------------------------------------------------------------------
    wait for 1000 ns;             -- to allow some time for completion
    report_alert_counters(FINAL); -- Report final counters and print conclusion for simulation (Success/Fail)
    log(ID_LOG_HDR, "SIMULATION COMPLETED", C_SCOPE);

    -- Finish the simulation
    std.env.stop;
    wait;  -- to stop completely

  end process p_main;

  
end architecture tb;
