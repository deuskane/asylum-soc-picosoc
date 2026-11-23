-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_bitbang_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_bitbang_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: JTAG over the UART pads (switches 11) in tb_PicoSoC : the
--              bytes of the OpenOCD remote_bitbang adapter (as the bitbang
--              driver of OpenOCD 0.12 sends them), sent to uart_rx_i with
--              the UART VIP (cfg.bitbang) ; the answers of jtag_bitbang to
--              'R' are received on the TX pad by the process p_bitbang of
--              tb_PicoSoC (t_bitbang_rsp)
--              * bitbang_send  : one command byte
--              * bitbang_tms   : TCK cycles with a TMS sequence, TCK low at
--                the end (bitbang_state_move of OpenOCD)
--              * bitbang_reset : Test-Logic-Reset, then Run-Test/Idle
--              * bitbang_idle  : Run-Test/Idle cycles
--              * bitbang_dmi   : DMI access of a RISC-V DTM (IR DMI already
--                selected) : request scan, idle cycles, nop scan that reads
--                the result (never busy at the byte rate of the UART)
--              * bitbang_write_ir, bitbang_scan_dr : IR / DR scan from
--                Run-Test/Idle to Run-Test/Idle, of the target TAP of the
--                JTAG BFM configuration (head / tail fields : the other TAPs
--                in BYPASS, as jtag_write_ir / jtag_scan_dr of the BFM) ;
--                each bit : TCK low with TMS and TDI, 'R', TCK high
--              Same jobs as tb_bitbang_bfm_pkg of asylum-debug-jtag, on the
--              records of tb_PicoSoC (a remote_bitbang BFM in
--              asylum-verification-uvvm would serve both)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_uart;
use     bitvis_vip_uart.uart_bfm_pkg.all;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;

library asylum;
use     asylum.WardRV_debug_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;

package tb_PicoSoC_bitbang_pkg is

  -- Answers kept : longer than the longest scan of the scenarios
  constant C_BITBANG_DEPTH : positive := 256;

  -- Answers of jtag_bitbang to 'R', received on the TX pad
  type t_bitbang_rsp is record
    cnt        : natural;                                      -- answers received since the start
    tdo        : std_logic_vector(C_BITBANG_DEPTH-1 downto 0); -- the last answers, the last one in the LSB
  end record t_bitbang_rsp;

  constant C_BITBANG_RSP_INIT : t_bitbang_rsp := (cnt => 0, tdo => (others => '0'));

  -- One command byte
  procedure bitbang_send
    (constant cmd      : in    character
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    );

  -- TCK cycles with the TMS sequence (left first), then TCK low
  procedure bitbang_tms
    (constant tms      : in    std_logic_vector
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    );

  -- Test-Logic-Reset (5 TCK with TMS = 1), then Run-Test/Idle
  procedure bitbang_reset
    (constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    );

  -- num_cycles TCK cycles in Run-Test/Idle
  procedure bitbang_idle
    (constant num_cycles : in    natural
    ;constant cfg        : in    t_tb_cfg
    ;signal   uart_rx    : inout std_logic
    );

  -- IR scan of the target TAP of config (ones to the other TAPs) ; checks
  -- the "01" captured by the target
  procedure bitbang_write_ir
    (constant ir_value : in    std_logic_vector
    ;constant msg      : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   rsp      : in    t_bitbang_rsp
    ;constant config   : in    t_jtag_bfm_config
    );

  -- DR scan of the target TAP of config (zeros to the other TAPs) : the
  -- captured value of the target in data_out
  procedure bitbang_scan_dr
    (constant data_value : in    std_logic_vector
    ;variable data_out   : out   std_logic_vector
    ;constant msg        : in    string
    ;constant cfg        : in    t_tb_cfg
    ;signal   uart_rx    : inout std_logic
    ;signal   rsp        : in    t_bitbang_rsp
    ;constant config     : in    t_jtag_bfm_config
    );

  -- DMI operations
  constant DMI_OP_NOP   : std_logic_vector(2-1 downto 0) := "00";
  constant DMI_OP_READ  : std_logic_vector(2-1 downto 0) := "01";
  constant DMI_OP_WRITE : std_logic_vector(2-1 downto 0) := "10";

  -- DMI access of the debugger at the position tap of the chain (its IR is
  -- DMI) : op, address, write data ; the read data in rdata
  procedure bitbang_dmi
    (constant op       : in    std_logic_vector(2-1 downto 0)
    ;constant addr     : in    std_logic_vector(DMI_ABITS-1 downto 0)
    ;constant wdata    : in    std_logic_vector(32-1 downto 0)
    ;variable rdata    : out   std_logic_vector(32-1 downto 0)
    ;constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;signal   uart_rx  : inout std_logic
    ;signal   rsp      : in    t_bitbang_rsp
    );

end package tb_PicoSoC_bitbang_pkg;

package body tb_PicoSoC_bitbang_pkg is

  procedure bitbang_send
    (constant cmd      : in    character
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ) is
  begin
    uart_transmit(data_value => std_logic_vector(to_unsigned(character'pos(cmd), 8)),
                  msg        => "remote_bitbang '" & cmd & "'",
                  tx         => uart_rx,
                  config     => cfg.bitbang,
                  scope      => C_TB_SCOPE);
  end procedure;

  -- '0'..'7' : TCK, TMS, TDI = bits 2, 1, 0
  procedure bitbang_write
    (constant tck      : in    std_logic
    ;constant tms      : in    std_logic
    ;constant tdi      : in    std_logic
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ) is
  begin
    bitbang_send(character'val(character'pos('0') + to_integer(unsigned'(tck & tms & tdi))), cfg, uart_rx);
  end procedure;

  procedure bitbang_tms
    (constant tms      : in    std_logic_vector
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ) is
  begin
    for i in tms'range loop
      bitbang_write('0', tms(i), '0', cfg, uart_rx);
      bitbang_write('1', tms(i), '0', cfg, uart_rx);
    end loop;
    bitbang_write('0', tms(tms'right), '0', cfg, uart_rx);
  end procedure;

  procedure bitbang_reset
    (constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ) is
  begin
    bitbang_tms("111110", cfg, uart_rx);
    log(ID_BFM, "bitbang_reset : Test-Logic-Reset, Run-Test/Idle", C_TB_SCOPE);
  end procedure;

  procedure bitbang_idle
    (constant num_cycles : in    natural
    ;constant cfg        : in    t_tb_cfg
    ;signal   uart_rx    : inout std_logic
    ) is
  begin
    for i in 1 to num_cycles loop
      bitbang_tms("0", cfg, uart_rx);
    end loop;
  end procedure;

  -- IR (ir) or DR scan from Run-Test/Idle to Run-Test/Idle : head bits,
  -- data, tail bits (LSB first), the answers of the data bits in data_out
  procedure bitbang_scan
    (constant ir         : in    boolean
    ;constant data_value : in    std_logic_vector
    ;variable data_out   : out   std_logic_vector
    ;constant cfg        : in    t_tb_cfg
    ;signal   uart_rx    : inout std_logic
    ;signal   rsp        : in    t_bitbang_rsp
    ;constant config     : in    t_jtag_bfm_config
    ) is
    alias    v_data      : std_logic_vector(data_value'length-1 downto 0) is data_value;
    variable v_out       : std_logic_vector(data_value'length-1 downto 0);
    variable v_head      : natural;
    variable v_tail      : natural;
    variable v_pad       : std_logic;
    variable v_tms       : std_logic;
    variable v_tdi       : std_logic;
    variable v_nb        : natural;
    constant C_FIRST     : natural := rsp.cnt;
  begin
    if ir
    then
      v_head := config.head_ir;
      v_tail := config.tail_ir;
      v_pad  := '1';  -- BYPASS
    else
      v_head := config.head_dr;
      v_tail := config.tail_dr;
      v_pad  := '0';
    end if;
    v_nb := v_head + v_data'length + v_tail;
    check_value(v_nb <= C_BITBANG_DEPTH, TB_ERROR, "bitbang scan longer than C_BITBANG_DEPTH", C_TB_SCOPE, ID_NEVER);

    -- Run-Test/Idle -> Select-DR (-> Select-IR) -> Capture -> Shift
    if ir
    then
      bitbang_tms("1100", cfg, uart_rx);
    else
      bitbang_tms("100" , cfg, uart_rx);
    end if;

    -- Shift, the last bit with TMS = 1 (Exit1)
    for i in 0 to v_nb-1 loop
      v_tms := '1' when i = v_nb-1 else '0';
      if (i >= v_head) and (i < v_head + v_data'length)
      then
        v_tdi := v_data(i-v_head);
      else
        v_tdi := v_pad;
      end if;
      bitbang_write('0', v_tms, v_tdi, cfg, uart_rx);
      bitbang_send ('R', cfg, uart_rx);
      bitbang_write('1', v_tms, v_tdi, cfg, uart_rx);
    end loop;

    -- Exit1 -> Update -> Run-Test/Idle
    bitbang_tms("10", cfg, uart_rx);

    -- Answers : bit i of the scan is the answer C_FIRST+i
    if rsp.cnt < C_FIRST + v_nb
    then
      wait until rsp.cnt >= C_FIRST + v_nb for cfg.timeout;
    end if;
    check_value(rsp.cnt = C_FIRST + v_nb, ERROR, "bitbang scan : " & integer'image(rsp.cnt - C_FIRST) & " answers to 'R' for " & integer'image(v_nb) & " bits", C_TB_SCOPE, ID_NEVER);
    for i in 0 to v_data'length-1 loop
      v_out(i) := rsp.tdo(v_nb-1-(v_head+i));
    end loop;
    data_out := v_out;
  end procedure;

  procedure bitbang_write_ir
    (constant ir_value : in    std_logic_vector
    ;constant msg      : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   uart_rx  : inout std_logic
    ;signal   rsp      : in    t_bitbang_rsp
    ;constant config   : in    t_jtag_bfm_config
    ) is
    variable v_capture : std_logic_vector(ir_value'length-1 downto 0);
  begin
    bitbang_scan(true, ir_value, v_capture, cfg, uart_rx, rsp, config);
    check_value(v_capture(1 downto 0), "01", ERROR, "bitbang_write_ir(x" & to_hstring(ir_value) & ") Capture-IR. " & msg, C_TB_SCOPE, msg_id => ID_NEVER);
    log(ID_BFM, "bitbang_write_ir(x" & to_hstring(ir_value) & ") completed. " & msg, C_TB_SCOPE);
  end procedure;

  procedure bitbang_scan_dr
    (constant data_value : in    std_logic_vector
    ;variable data_out   : out   std_logic_vector
    ;constant msg        : in    string
    ;constant cfg        : in    t_tb_cfg
    ;signal   uart_rx    : inout std_logic
    ;signal   rsp        : in    t_bitbang_rsp
    ;constant config     : in    t_jtag_bfm_config
    ) is
    variable v_out       : std_logic_vector(data_value'length-1 downto 0);
  begin
    bitbang_scan(false, data_value, v_out, cfg, uart_rx, rsp, config);
    log(ID_BFM, "bitbang_scan_dr(x" & to_hstring(data_value) & ") => x" & to_hstring(v_out) & ". " & msg, C_TB_SCOPE);
    data_out := v_out;
  end procedure;

  procedure bitbang_dmi
    (constant op       : in    std_logic_vector(2-1 downto 0)
    ;constant addr     : in    std_logic_vector(DMI_ABITS-1 downto 0)
    ;constant wdata    : in    std_logic_vector(32-1 downto 0)
    ;variable rdata    : out   std_logic_vector(32-1 downto 0)
    ;constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;signal   uart_rx  : inout std_logic
    ;signal   rsp      : in    t_bitbang_rsp
    ) is
    -- Run-Test/Idle cycles after a dmi scan (dtmcs.idle)
    constant C_DMI_IDLE  : natural := 5;
    variable v_dmi       : std_logic_vector(DMI_ABITS+32+2-1 downto 0);
  begin
    bitbang_scan_dr(addr & wdata & op, v_dmi, "dmi request", cfg, uart_rx, rsp, jtag_config(cfg, tap));
    bitbang_idle   (C_DMI_IDLE, cfg, uart_rx);
    bitbang_scan_dr(addr & x"00000000" & DMI_OP_NOP, v_dmi, "dmi result", cfg, uart_rx, rsp, jtag_config(cfg, tap));
    bitbang_idle   (C_DMI_IDLE, cfg, uart_rx);
    check_value    (v_dmi(1 downto 0), DMI_OP_NOP, ERROR, "DMI access 0x" & to_hstring(addr) & " : result op (not busy)", C_TB_SCOPE, msg_id => ID_NEVER);
    log(ID_BFM, "DMI 0x" & to_hstring(addr) & " : op " & to_string(op) & ", 0x" & to_hstring(wdata) & " => 0x" & to_hstring(v_dmi(33 downto 2)), C_TB_SCOPE);
    rdata := v_dmi(33 downto 2);
  end procedure;

end package body tb_PicoSoC_bitbang_pkg;
