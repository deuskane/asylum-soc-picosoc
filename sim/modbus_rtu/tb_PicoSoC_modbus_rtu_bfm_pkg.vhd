-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_modbus_rtu_bfm_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_modbus_rtu_bfm_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Helpers of the tb_PicoSoC_modbus_rtu scenarios : Modbus RTU
--              master on the UART of the SoC (UART VIP), read / write of a
--              SoC address by esw/protocol/user_modbus_rtu.c (function codes 0x03 /
--              0x06, CRC16 0xA001), error injection
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (helpers of tb_PicoSoC_modbus_rtu)
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
use     asylum.gpio_irq_csr_pkg.all;

package tb_PicoSoC_modbus_rtu_bfm_pkg is

  constant C_TB_SCOPE        : string := "TB_MODBUS";

  -- Constants of the scenarios (computed from the generics in tb_PicoSoC_modbus_rtu)
  type t_tb_cfg is record
    clk_period : time;               -- period of clk_i
    fault_on   : std_logic;          -- active level of inject_error_i (USER_FAULT_POLARITY)
    uart       : t_uart_bfm_config;  -- UART VIP configuration
  end record t_tb_cfg;

  -- =====[ Timing ]==============================
  constant C_ERROR_DURATION  : time    :=   2 us; -- Error injection pulse
  constant C_ERROR_LATENCY   : time    :=  20 us; -- Time between error injection and error detection
  constant C_RESET_LATENCY   : time    := 200 us; -- Firmware ready after a reset
  constant C_FRAME_GAP       : time    :=  35 us; -- Silence before a Modbus frame

  -- =====[ MODBUS ]==============================
  constant C_MODBUS_SLAVE_ID : std_logic_vector(8-1 downto 0) := x"5A";
  constant C_MODBUS_READ     : std_logic_vector(8-1 downto 0) := x"03";
  constant C_MODBUS_WRITE    : std_logic_vector(8-1 downto 0) := x"06";

  -- =====[ SOC ADDRMAP ]=========================
  constant C_SWITCH_DATA     : std_logic_vector(8-1 downto 0) := std_logic_vector(unsigned(PICOSOC_USER_SWITCH_BA) + resize(GPIO_IRQ_DATA, 8));
  constant C_LED0_DATA       : std_logic_vector(8-1 downto 0) := std_logic_vector(unsigned(PICOSOC_USER_LED0_BA  ) + resize(GPIO_IRQ_DATA, 8));

  type t_data_array is array (natural range <>) of std_logic_vector(8-1 downto 0);

  -- Never set : the UART expects end on their timeout
  signal   uart_no_terminate : std_logic := '0';

  -- Modbus write of one SoC address (function 0x06), then the echo of the slave
  -- (id = C_MODBUS_SLAVE_ID or 0x00 broadcast : written; another id : ignored, no answer)
  procedure modbus_write
    (constant addr     : in    std_logic_vector
    ;constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;constant id       : in    std_logic_vector := C_MODBUS_SLAVE_ID
    );

  -- Modbus read of data_array'length SoC addresses (function 0x03), answer checked
  procedure modbus_read
    (constant addr       : in    std_logic_vector
    ;constant data_array : in    t_data_array
    ;constant msg        : in    string
    ;constant cfg        : in    t_tb_cfg
    ;signal   uart_rx    : inout std_logic
    ;signal   uart_tx    : in    std_logic
    );

  -- Wait until LED0 = exp (one clock period at most)
  procedure check_led0
    (signal   led0     : in    std_logic_vector
    ;constant exp      : in    std_logic_vector
    ;constant msg      : in    string
    ;constant cfg      : in    t_tb_cfg
    );

  -- Wait until led_diff = number of resets of the user SoC (supervisor counter)
  procedure check_led_diff
    (signal   led_diff : in    std_logic_vector
    ;constant nb_reset : in    natural
    ;constant msg      : in    string
    );

  -- Error injected in a CPU during C_ERROR_DURATION, then C_ERROR_LATENCY
  procedure inject_error
    (constant cpu      : in    natural
    ;constant cfg      : in    t_tb_cfg
    ;signal   inject   : out   std_logic_vector
    );

  -- Active level of an input of polarity "high" / "low"
  function active_level
    (polarity : string
    ) return std_logic;

end package tb_PicoSoC_modbus_rtu_bfm_pkg;

package body tb_PicoSoC_modbus_rtu_bfm_pkg is

  -- CRC16 of Modbus (polynom 0xA001, reflected)
  function crc16_next
    (crc  : std_logic_vector(16-1 downto 0)
    ;data : std_logic_vector( 8-1 downto 0)
    ) return std_logic_vector is
    variable v_crc : std_logic_vector(16-1 downto 0);
  begin
    v_crc := crc xor (x"00" & data);
    for i in 0 to 8-1 loop
      if v_crc(0) = '1'
      then
        v_crc := ('0' & v_crc(16-1 downto 1)) xor x"A001";
      else
        v_crc :=  '0' & v_crc(16-1 downto 1);
      end if;
    end loop;
    return v_crc;
  end function;

  -- Send a byte
  procedure send
    (constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ) is
  begin
    uart_transmit(data_value => data,
                  msg        => msg,
                  tx         => uart_rx,
                  config     => cfg.uart,
                  scope      => C_TB_SCOPE);
  end procedure;

  -- Expect a byte
  procedure expect
    (constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_tx  : in    std_logic
    ) is
  begin
    uart_expect(data_exp       => data,
                msg            => msg,
                rx             => uart_tx,
                terminate_loop => uart_no_terminate,
                max_receptions => 1,
                timeout        => 1 ms,
                alert_level    => ERROR,
                config         => cfg.uart,
                scope          => C_TB_SCOPE);
  end procedure;

  -- Send a byte, update the CRC
  procedure tx
    (constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;variable crc      : inout std_logic_vector
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ) is
  begin
    send(data, msg, cfg, uart_rx);
    crc := crc16_next(crc, data);
  end procedure;

  -- Expect a byte, update the CRC
  procedure rx
    (constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;variable crc      : inout std_logic_vector
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_tx  : in    std_logic
    ) is
  begin
    expect(data, msg, cfg, uart_tx);
    crc := crc16_next(crc, data);
  end procedure;

  procedure modbus_write
    (constant addr     : in    std_logic_vector
    ;constant data     : in    std_logic_vector
    ;constant msg      : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   uart_tx  : in    std_logic
    ;constant id       : in    std_logic_vector := C_MODBUS_SLAVE_ID
    ) is
    variable v_crc     : std_logic_vector(16-1 downto 0);
  begin
    log(ID_SEQUENCER_SUB, msg, C_TB_SCOPE);
    v_crc := (others => '1');
    tx(id            , "MODBUS TX Slave ID"          , v_crc, cfg, uart_rx);
    tx(C_MODBUS_WRITE, "MODBUS TX Write"             , v_crc, cfg, uart_rx);
    tx(x"00"         , "MODBUS TX Addr MSB (Ignored)", v_crc, cfg, uart_rx);
    tx(addr          , "MODBUS TX Addr LSB"          , v_crc, cfg, uart_rx);
    tx(x"00"         , "MODBUS TX Data MSB (Ignored)", v_crc, cfg, uart_rx);
    tx(data          , "MODBUS TX Data LSB"          , v_crc, cfg, uart_rx);
    send(v_crc( 7 downto 0), "MODBUS TX CRC", cfg, uart_rx);
    send(v_crc(15 downto 8), "MODBUS TX CRC", cfg, uart_rx);

    if (id = C_MODBUS_SLAVE_ID)
    then
      v_crc := (others => '1');
      rx(id            , "MODBUS RX Slave ID"          , v_crc, cfg, uart_tx);
      rx(C_MODBUS_WRITE, "MODBUS RX Write"             , v_crc, cfg, uart_tx);
      rx(x"00"         , "MODBUS RX Addr MSB (Ignored)", v_crc, cfg, uart_tx);
      rx(addr          , "MODBUS RX Addr LSB"          , v_crc, cfg, uart_tx);
      rx(x"00"         , "MODBUS RX Data MSB (Ignored)", v_crc, cfg, uart_tx);
      rx(data          , "MODBUS RX Data LSB"          , v_crc, cfg, uart_tx);
      expect(v_crc( 7 downto 0), "MODBUS RX CRC", cfg, uart_tx);
      expect(v_crc(15 downto 8), "MODBUS RX CRC", cfg, uart_tx);
    else
      -- Another slave id : no answer
      wait for 200 us;
      check_stable(uart_tx, 200 us, ERROR, "No answer to the slave id 0x" & to_hstring(id), C_TB_SCOPE);
    end if;
  end procedure;

  procedure modbus_read
    (constant addr       : in    std_logic_vector
    ;constant data_array : in    t_data_array
    ;constant msg        : in    string
    ;constant cfg        : in    t_tb_cfg
    ;signal   uart_rx    : inout std_logic
    ;signal   uart_tx    : in    std_logic
    ) is
    constant C_LEN       : natural := data_array'length;
    variable v_crc       : std_logic_vector(16-1 downto 0);
  begin
    log(ID_SEQUENCER_SUB, msg, C_TB_SCOPE);
    v_crc := (others => '1');
    tx(C_MODBUS_SLAVE_ID                       , "MODBUS TX Slave ID"          , v_crc, cfg, uart_rx);
    tx(C_MODBUS_READ                           , "MODBUS TX Read"              , v_crc, cfg, uart_rx);
    tx(x"00"                                   , "MODBUS TX Addr MSB (Ignored)", v_crc, cfg, uart_rx);
    tx(addr                                    , "MODBUS TX Addr LSB"          , v_crc, cfg, uart_rx);
    tx(x"00"                                   , "MODBUS TX Len MSB (Ignored)" , v_crc, cfg, uart_rx);
    tx(std_logic_vector(to_unsigned(C_LEN, 8)) , "MODBUS TX Len LSB"           , v_crc, cfg, uart_rx);
    send(v_crc( 7 downto 0), "MODBUS TX CRC", cfg, uart_rx);
    send(v_crc(15 downto 8), "MODBUS TX CRC", cfg, uart_rx);

    v_crc := (others => '1');
    rx(C_MODBUS_SLAVE_ID                       , "MODBUS RX Slave ID"          , v_crc, cfg, uart_tx);
    rx(C_MODBUS_READ                           , "MODBUS RX Read"              , v_crc, cfg, uart_tx);
    rx(std_logic_vector(to_unsigned(2*C_LEN, 8)), "MODBUS RX Byte Count"       , v_crc, cfg, uart_tx);
    for i in data_array'range loop
      rx(x"00"                                 , "MODBUS RX Data MSB (Ignored)", v_crc, cfg, uart_tx);
      rx(data_array(i)                         , "MODBUS RX Data LSB"          , v_crc, cfg, uart_tx);
    end loop;
    expect(v_crc( 7 downto 0), "MODBUS RX CRC", cfg, uart_tx);
    expect(v_crc(15 downto 8), "MODBUS RX CRC", cfg, uart_tx);
  end procedure;

  procedure check_led0
    (signal   led0     : in    std_logic_vector
    ;constant exp      : in    std_logic_vector
    ;constant msg      : in    string
    ;constant cfg      : in    t_tb_cfg
    ) is
  begin
    await_value(target      => led0,
                exp         => exp,
                min_time    => 0 ns,
                max_time    => cfg.clk_period,
                alert_level => ERROR,
                msg         => msg,
                scope       => C_TB_SCOPE);
  end procedure;

  procedure check_led_diff
    (signal   led_diff : in    std_logic_vector
    ;constant nb_reset : in    natural
    ;constant msg      : in    string
    ) is
  begin
    await_value(target      => led_diff,
                exp         => std_logic_vector(to_unsigned(nb_reset, led_diff'length)),
                min_time    => 0 ns,
                max_time    => C_RESET_LATENCY,
                alert_level => ERROR,
                msg         => msg,
                scope       => C_TB_SCOPE);
  end procedure;

  function active_level
    (polarity : string
    ) return std_logic is
  begin
    if polarity = "high"
    then
      return '1';
    else
      return '0';
    end if;
  end function;

  procedure inject_error
    (constant cpu      : in    natural
    ;constant cfg      : in    t_tb_cfg
    ;signal   inject   : out   std_logic_vector
    ) is
  begin
    log(ID_SEQUENCER_SUB, "Inject an error in CPU" & integer'image(cpu), C_TB_SCOPE);
    inject      <= (inject'range => not cfg.fault_on);
    inject(cpu) <= cfg.fault_on;
    wait for C_ERROR_DURATION;
    inject      <= (inject'range => not cfg.fault_on);
    wait for C_ERROR_LATENCY;
  end procedure;

end package body tb_PicoSoC_modbus_rtu_bfm_pkg;
