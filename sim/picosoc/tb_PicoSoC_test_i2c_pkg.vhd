-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_test_i2c_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_test_i2c_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario test_i2c of tb_PicoSoC, from reset (firmware
--              esw/test/test_i2c.c, I2C master and slave of the SoC) with the
--              UVVM I2C BFM :
--              * BFM slave at C_SLAVE : write of C_MASTER_DATA by the SoC
--                (address, bytes and ACKs checked), then read : the BFM
--                sends C_MASTER_DATA back, checks the ACK, then the NACK of
--                the last byte
--              * write of the SoC to an address without slave : address
--                byte sampled, SCL period (100 kHz, reset value of the
--                prescaler)
--              * BFM master, once LED0 = 1 : write of C_SLAVE_DATA to the
--                slave of the SoC at C_ME (ACKs checked), then read : the
--                bytes sent back by the firmware are checked ; end of the
--                read acknowledged on the switches
--              * result line "PASS", then SCL and SDA released
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-21  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_i2c;
use     bitvis_vip_i2c.i2c_bfm_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_test_i2c_pkg is

  -- Transfers between the I2C of the SoC and the BFM
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   i2c_if   : inout t_i2c_if
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_test_i2c_pkg;

package body tb_PicoSoC_test_i2c_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   i2c_if   : inout t_i2c_if
    ;signal   uart_tx  : in    std_logic
    ) is
    -- Constants of esw/test/test_i2c.c
    constant C_SLAVE       : natural      := 16#50#;          -- I2C_SLAVE : BFM slave
    constant C_NO_SLAVE    : natural      := 16#51#;          -- I2C_NO_SLAVE
    constant C_ME          : natural      := 16#3A#;          -- I2C_ME : slave of the SoC
    constant C_MASTER_DATA : t_byte_array := (x"A5", x"5A");  -- MASTER_DATA0 / 1
    constant C_SLAVE_DATA  : t_byte_array := (x"3C", x"C3");  -- SLAVE_DATA0 / 1
    constant C_BIT_TIME    : time         := 10 us;           -- 100 kHz
    variable v_config      : t_i2c_bfm_config := C_I2C_BFM_CONFIG_DEFAULT;
    variable v_addr        : std_logic_vector(8-1 downto 0);
    variable v_rise        : time;
  begin
    log(ID_SEQUENCER, "test_i2c : I2C master and slave of the SoC, UVVM I2C BFM", C_TB_SCOPE);

    -- BFM : SCL at 100 kHz in master mode (a stretching of the slave of the
    -- SoC up to one bit time), START / STOP timings of one bit time, waits
    -- for the firmware up to cfg.timeout in slave mode
    v_config.i2c_bit_time                    := C_BIT_TIME;
    v_config.i2c_bit_time_severity           := ERROR;
    v_config.master_sda_to_scl               := C_BIT_TIME;
    v_config.master_scl_to_sda               := C_BIT_TIME;
    v_config.master_stop_condition_hold_time := C_BIT_TIME;
    v_config.max_wait_scl_change             := cfg.timeout;
    v_config.max_wait_sda_change             := cfg.timeout;
    v_config.max_wait_scl_change_severity    := ERROR;
    v_config.max_wait_sda_change_severity    := ERROR;
    v_config.acknowledge_severity            := ERROR;
    v_config.slave_mode_address              := to_unsigned(C_SLAVE, 10);
    v_config.slave_mode_address_severity     := ERROR;
    v_config.slave_rw_bit_severity           := ERROR;

    -- Master of the SoC : write, then read back of the same bytes
    i2c_slave_check   (C_MASTER_DATA, "SoC master write : address + W and bytes", i2c_if, C_WRITE_BIT, ERROR, C_TB_SCOPE, shared_msg_id_panel, v_config);
    i2c_slave_transmit(C_MASTER_DATA, "SoC master read : bytes sent back"        , i2c_if,                     C_TB_SCOPE, shared_msg_id_panel, v_config);

    -- Master of the SoC, address without slave (nobody answers, NACK
    -- checked by the firmware) : address byte sampled on the rising edges
    -- of SCL, SCL period between the first two
    await_value(i2c_if.sda, '0', MATCH_STD, 0 ns, cfg.timeout, ERROR, "SoC master : START of the write to an address without slave", C_TB_SCOPE);
    for i in 8-1 downto 0 loop
      await_value(i2c_if.scl, '0', MATCH_STD, 0 ns, cfg.timeout, ERROR, "SCL low" , C_TB_SCOPE);
      await_value(i2c_if.scl, '1', MATCH_STD, 0 ns, cfg.timeout, ERROR, "SCL high", C_TB_SCOPE);
      v_addr(i) := to_x01(i2c_if.sda);
      if i = 7
      then
        v_rise := now;
      elsif i = 6
      then
        check_value_in_range(now - v_rise, C_BIT_TIME, C_BIT_TIME*100/95, ERROR,
                             "SCL period of the reset value of the prescaler : 95 to 100 kHz", C_TB_SCOPE);
      end if;
    end loop;
    check_value(v_addr, std_logic_vector(to_unsigned(C_NO_SLAVE, 7)) & C_WRITE_BIT, ERROR, "SoC master : address + W without slave", C_TB_SCOPE);

    -- Slave of the SoC : write, then read back by the BFM master
    wait_value(led0, x"01", cfg, "LED0 = 1 : slave of the SoC served by the firmware");
    i2c_master_transmit(to_unsigned(C_ME, 7), C_SLAVE_DATA, "SoC slave : write of the BFM master", i2c_if, RELEASE_LINE_AFTER_TRANSFER,        C_TB_SCOPE, shared_msg_id_panel, v_config);
    i2c_master_check   (to_unsigned(C_ME, 7), C_SLAVE_DATA, "SoC slave : bytes read back"       , i2c_if, RELEASE_LINE_AFTER_TRANSFER, ERROR, C_TB_SCOPE, shared_msg_id_panel, v_config);

    -- End of the read acknowledged, the firmware then prints its result ;
    -- bus released after the last STOP
    set_slv    (x"01", clk, switch);
    wait_pass  ("test_i2c", uart_tx, cfg);
    check_value(to_x01(i2c_if.scl), '1', ERROR, "SCL released (pull-up)", C_TB_SCOPE);
    check_value(to_x01(i2c_if.sda), '1', ERROR, "SDA released (pull-up)", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_test_i2c_pkg;
