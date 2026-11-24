-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_bitbang_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_bitbang_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: JTAG over the UART pads (debug_mux_sel_i 11) in tb_PicoSoC,
--              PicoSoC part : the scenarios send the bytes of the OpenOCD
--              remote_bitbang adapter with the remote_bitbang BFM
--              rbb_bfm_pkg of asylum-verification-uvvm (UART frames on
--              uart_rx_i, answers to 'R' received on the TX pad by
--              rbb_uart_monitor in tb_PicoSoC)
--              * rbb_config  : BFM configuration of tb_PicoSoC (UART frames
--                at JTAG_BAUD_RATE, timeout of the testbench)
--              * bitbang_reset, bitbang_write_ir, bitbang_scan_dr : one BFM
--                call each (rbb_reset, rbb_write_ir, rbb_scan_dr) with the
--                configuration of tb_PicoSoC and the JTAG BFM configuration
--                of a TAP of the chain (jtag_config of tb_PicoSoC_jtag_pkg)
--              * bitbang_dmi : DMI access of a RISC-V DTM (IR DMI already
--                selected) : request scan, idle cycles, nop scan that reads
--                the result (never busy at the byte rate of the UART)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created
-- 2026-11-24  1.1      mrosiere Bytes, TMS moves, scans and answers by
--                               rbb_bfm_pkg (asylum:verification:uvvm
--                               1.3.0), one BFM call per helper
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;
use     asylum_uvvm.rbb_bfm_pkg.all;

library asylum;
use     asylum.WardRV_debug_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;

package tb_PicoSoC_bitbang_pkg is

  -- remote_bitbang BFM configuration : UART frames of cfg.bitbang
  -- (JTAG_BAUD_RATE), answers waited for cfg.timeout
  function rbb_config
    (cfg      : t_tb_cfg
    ) return t_rbb_bfm_config;

  -- Test-Logic-Reset (5 TCK with TMS = 1), then Run-Test/Idle
  procedure bitbang_reset
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   rbb_if   : inout t_rbb_if
    );

  -- IR scan of the target TAP of config (ones to the other TAPs) ; checks
  -- the "01" captured by the target
  procedure bitbang_write_ir
    (constant ir_value : in    std_logic_vector
    ;constant msg      : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   rbb_if   : inout t_rbb_if
    ;signal   bitbang  : in    t_rbb_answers
    ;constant config   : in    t_jtag_bfm_config
    );

  -- DR scan of the target TAP of config (zeros to the other TAPs) : the
  -- captured value of the target in data_out
  procedure bitbang_scan_dr
    (constant data_value : in    std_logic_vector
    ;variable data_out   : out   std_logic_vector
    ;constant msg        : in    string
    ;constant cfg        : in    t_tb_cfg
    ;signal   clk        : in    std_logic
    ;signal   rbb_if     : inout t_rbb_if
    ;signal   bitbang    : in    t_rbb_answers
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
    ;signal   clk      : in    std_logic
    ;signal   rbb_if   : inout t_rbb_if
    ;signal   bitbang  : in    t_rbb_answers
    );

end package tb_PicoSoC_bitbang_pkg;

package body tb_PicoSoC_bitbang_pkg is

  function rbb_config
    (cfg      : t_tb_cfg
    ) return t_rbb_bfm_config is
    variable v_config : t_rbb_bfm_config := C_RBB_BFM_CONFIG_DEFAULT;
  begin
    v_config.uart        := true;
    v_config.uart_config := cfg.bitbang;
    v_config.timeout     := cfg.timeout;
    return v_config;
  end function;

  procedure bitbang_reset
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   rbb_if   : inout t_rbb_if
    ) is
  begin
    rbb_reset(msg         => "Test-Logic-Reset, Run-Test/Idle",
              clk         => clk,
              rbb_if      => rbb_if,
              scope       => C_TB_SCOPE,
              config      => rbb_config(cfg),
              jtag_config => jtag_config(cfg.jtag.nb_tap));  -- No TRST*
  end procedure;

  procedure bitbang_write_ir
    (constant ir_value : in    std_logic_vector
    ;constant msg      : in    string
    ;constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   rbb_if   : inout t_rbb_if
    ;signal   bitbang  : in    t_rbb_answers
    ;constant config   : in    t_jtag_bfm_config
    ) is
  begin
    rbb_write_ir(ir_value    => ir_value,
                 msg         => msg,
                 clk         => clk,
                 rbb_if      => rbb_if,
                 answers     => bitbang,
                 scope       => C_TB_SCOPE,
                 config      => rbb_config(cfg),
                 jtag_config => config);
  end procedure;

  procedure bitbang_scan_dr
    (constant data_value : in    std_logic_vector
    ;variable data_out   : out   std_logic_vector
    ;constant msg        : in    string
    ;constant cfg        : in    t_tb_cfg
    ;signal   clk        : in    std_logic
    ;signal   rbb_if     : inout t_rbb_if
    ;signal   bitbang    : in    t_rbb_answers
    ;constant config     : in    t_jtag_bfm_config
    ) is
  begin
    rbb_scan_dr(data_value  => data_value,
                data_out    => data_out,
                msg         => msg,
                clk         => clk,
                rbb_if      => rbb_if,
                answers     => bitbang,
                scope       => C_TB_SCOPE,
                config      => rbb_config(cfg),
                jtag_config => config);
  end procedure;

  procedure bitbang_dmi
    (constant op       : in    std_logic_vector(2-1 downto 0)
    ;constant addr     : in    std_logic_vector(DMI_ABITS-1 downto 0)
    ;constant wdata    : in    std_logic_vector(32-1 downto 0)
    ;variable rdata    : out   std_logic_vector(32-1 downto 0)
    ;constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;signal   clk      : in    std_logic
    ;signal   rbb_if   : inout t_rbb_if
    ;signal   bitbang  : in    t_rbb_answers
    ) is
    -- Run-Test/Idle cycles after a dmi scan (dtmcs.idle)
    constant C_DMI_IDLE  : natural := 5;
    variable v_dmi       : std_logic_vector(DMI_ABITS+32+2-1 downto 0);

    procedure idle(constant msg : in string) is
    begin
      rbb_idle(num_cycles => C_DMI_IDLE,
               msg        => msg,
               clk        => clk,
               rbb_if     => rbb_if,
               scope      => C_TB_SCOPE,
               config     => rbb_config(cfg));
    end procedure;

  begin
    bitbang_scan_dr(addr & wdata       & op        , v_dmi, "dmi request", cfg, clk, rbb_if, bitbang, jtag_config(cfg, tap));
    idle           ("after the dmi request");
    bitbang_scan_dr(addr & x"00000000" & DMI_OP_NOP, v_dmi, "dmi result" , cfg, clk, rbb_if, bitbang, jtag_config(cfg, tap));
    idle           ("after the dmi result");
    check_value    (v_dmi(1 downto 0), DMI_OP_NOP, ERROR, "DMI access 0x" & to_hstring(addr) & " : result op (not busy)", C_TB_SCOPE, msg_id => ID_NEVER);
    log(ID_BFM, "DMI 0x" & to_hstring(addr) & " : op " & to_string(op) & ", 0x" & to_hstring(wdata) & " => 0x" & to_hstring(v_dmi(33 downto 2)), C_TB_SCOPE);
    rdata := v_dmi(33 downto 2);
  end procedure;

end package body tb_PicoSoC_bitbang_pkg;
