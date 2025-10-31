-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_uart
-- Project    : 
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_uart.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2025-10-23
-- Last update: 2025-10-31
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
    ;UART_DEPTH_TX    : natural  := 8
    ;UART_DEPTH_RX    : natural  := 8
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
           
  -- =====[ TB Signals ]==========================
  signal   cke                     : boolean   := false;

  signal   uart_terminate_loop     : std_logic := '0';
  signal   debug_crc               : std_logic_vector(16-1 downto 0);
  
  -- =====[ TB Constants ]========================
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

  -- =====[ MODBUS ]==============================
  constant C_MODBUS_SLAVE_ID       : std_logic_vector(8-1 downto 0) := x"01";
  constant C_MODBUS_READ           : std_logic_vector(8-1 downto 0) := x"03";
  constant C_MODBUS_WRITE          : std_logic_vector(8-1 downto 0) := x"06";

  -- =====[ SOC ADDRMAP ]=========================
  constant C_SWITCH_BA             : std_logic_vector(8-1 downto 0) := x"10";
  constant C_LED0_BA               : std_logic_vector(8-1 downto 0) := x"20";
  constant C_LED1_BA               : std_logic_vector(8-1 downto 0) := x"40";
  constant C_UART_BA               : std_logic_vector(8-1 downto 0) := x"80";
  constant C_SPI_BA                : std_logic_vector(8-1 downto 0) := x"08";
  constant C_GIC_BA                : std_logic_vector(8-1 downto 0) := x"F0";

  -- =====[ Function ]============================
  -- Fonction CRC16 (Modbus, polynôme 0xA001)
  function crc16_next(
    crc  : std_logic_vector(16-1 downto 0);
    data : std_logic_vector(8-1 downto 0)
    ) return std_logic_vector is
    variable crc_var  : std_logic_vector(16-1 downto 0) := crc;
    variable d        : std_logic_vector(8-1 downto 0) := data;
    variable i        : integer;
  begin
    crc_var := crc xor ("00000000" & d);  -- concatène 8 bits de 0 avec data

    
    for i in 0 to 8-1 loop
      --report "CRC : " & to_hstring(crc_var);
      if crc_var(0) = '1' then
        crc_var := ('0' & crc_var(16-1 downto 1)) xor x"A001";
      else
        crc_var := '0' & crc_var(16-1 downto 1);
      end if;
    end loop;
    --report "CRC : " & to_hstring(crc_var);

    return crc_var;
  end function;
  
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
    ,UART_DEPTH_TX    => UART_DEPTH_TX
    ,UART_DEPTH_RX    => UART_DEPTH_RX
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

    variable modbus_crc : std_logic_vector(16-1 downto 0);

    procedure modbus_tx_begin(
      constant msg          : in string
      ) is
    begin
      log(ID_LOG_HDR, msg, C_SCOPE);

      modbus_crc         := (others => '1');
      debug_crc          <= modbus_crc;
    end;
    
    procedure modbus_tx(
      constant data_value   : in std_logic_vector;
      constant msg          : in string
      ) is
    begin
      uart_transmit(data_value,msg,uart_rx_i,C_UART_BFM_CONFIG);
      modbus_crc := crc16_next(modbus_crc,data_value);
      debug_crc  <= modbus_crc;
    end;

    procedure modbus_tx_end(
      constant msg          : in string
      ) is
    begin
      uart_transmit(modbus_crc( 7 downto 0),msg,uart_rx_i,C_UART_BFM_CONFIG);
      uart_transmit(modbus_crc(15 downto 8),msg,uart_rx_i,C_UART_BFM_CONFIG);
    end;

    procedure modbus_rx_begin(
      constant msg          : in string
      ) is
    begin
      log(ID_LOG_HDR, msg, C_SCOPE);

      modbus_crc         := (others => '1');
      debug_crc          <= modbus_crc;
    end;
    
    procedure modbus_rx(
      constant data_exp     : in std_logic_vector;
      constant msg          : in string
      ) is
    begin
      uart_expect(data_exp,msg,uart_tx_o,uart_terminate_loop,1,1 ms,ERROR, C_UART_BFM_CONFIG);
      modbus_crc := crc16_next(modbus_crc,data_exp);
      debug_crc  <= modbus_crc;
    end;

    procedure modbus_rx_end(
      constant msg          : in string
      ) is
    begin
      uart_expect(modbus_crc( 7 downto 0),msg,uart_tx_o,uart_terminate_loop,1,1 ms,ERROR, C_UART_BFM_CONFIG);
      uart_expect(modbus_crc(15 downto 8),msg,uart_tx_o,uart_terminate_loop,1,1 ms,ERROR, C_UART_BFM_CONFIG);
    end;

    
    procedure modbus_write(
      constant addr : in std_logic_vector;
      constant data : in std_logic_vector;
      constant msg  : in string
      ) is
      begin
        modbus_tx_begin(msg);    
        modbus_tx      (C_MODBUS_SLAVE_ID,"MODBUS TX Slave ID"             );
        modbus_tx      (C_MODBUS_WRITE,   "MODBUS TX Write"                );
        modbus_tx      (x"00",            "MODBUS TX Addr MSB (Ignored)"   );
        modbus_tx      (addr,             "MODBUS TX Addr LSB"             );
        modbus_tx      (x"00",            "MODBUS TX Data MSB (Ignored)"   );
        modbus_tx      (data,             "MODBUS TX Data LSB"             );
        modbus_tx_end  (                  "MODBUS TX CRC"                  );    

        modbus_rx_begin(msg);    
        modbus_rx      (C_MODBUS_SLAVE_ID,"MODBUS TX Slave ID"             );
        modbus_rx      (C_MODBUS_WRITE,   "MODBUS TX Write"                );
        modbus_rx      (x"00",            "MODBUS TX Addr MSB (Ignored)"   );
        modbus_rx      (addr,             "MODBUS TX Addr LSB"             );
        modbus_rx      (x"00",            "MODBUS TX Data MSB (Ignored)"   );
        modbus_rx      (data,             "MODBUS TX Data LSB"             );
        modbus_rx_end  (                  "MODBUS TX CRC"                  );    

      end;

    type t_data_array is array (natural range <>) of std_logic_vector(7 downto 0);
      
    procedure modbus_read(
      constant addr       : in std_logic_vector;
      constant data_array : in t_data_array;
      constant msg        : in string
      ) is

      variable len : natural := data_array'length;
    begin
      modbus_tx_begin(msg);    
      modbus_tx      (C_MODBUS_SLAVE_ID, "MODBUS TX Slave ID");
      modbus_tx      (C_MODBUS_READ,     "MODBUS TX Read");
      modbus_tx      (x"00",             "MODBUS TX Addr MSB (Ignored)");
      modbus_tx      (addr,              "MODBUS TX Addr LSB");
      modbus_tx      (x"00",             "MODBUS TX Len MSB (Ignored)");
      modbus_tx      (std_logic_vector(to_unsigned(len, 8)), "MODBUS TX Len LSB");
      modbus_tx_end  ("MODBUS TX CRC");

      modbus_rx_begin(msg);    
      modbus_rx      (C_MODBUS_SLAVE_ID, "MODBUS RX Slave ID");
      modbus_rx      (C_MODBUS_READ,     "MODBUS RX Read");
      modbus_rx      (std_logic_vector(to_unsigned(len * 2, 8)), "MODBUS RX Byte Count");

      for i in 0 to len - 1 loop
        modbus_rx(x"00", "MODBUS RX Data MSB (Ignored)");
        modbus_rx(data_array(i), "MODBUS RX Data LSB");
      end loop;

      modbus_rx_end("MODBUS RX CRC");
    end procedure;      

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

    --==================================================================================================
    -- Test case
    --------------------------------------------------------------------------------------
    
    modbus_write(C_LED0_BA  ,x"01",        "Write LED0 Data <= 0x01");
    modbus_read (C_LED0_BA  ,(0 => x"01"), "Read  LED0 Data");
    modbus_read (C_LED0_BA  ,(0 => x"01",
                              1 => x"FF"), "Read  LED0 Data & OE");
    
    switch_i <= x"5A";
    modbus_read (C_SWITCH_BA,(0 => x"5A"), "Read  SWITCH Data");
    switch_i <= x"3C";
    modbus_read (C_SWITCH_BA,(0 => x"3C"), "Read  SWITCH Data");
    switch_i <= x"1E";
    modbus_read (C_SWITCH_BA,(0 => x"1E"), "Read  SWITCH Data");
    
    -- Checks modbus error
    -- 1) bad slave id
    -- 2) bad function code
    -- 3) write addr msb
    -- 4) write data msb
    -- 5) read addr msb
    -- 6) read data msb
    -- 7) bad crc
        
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
