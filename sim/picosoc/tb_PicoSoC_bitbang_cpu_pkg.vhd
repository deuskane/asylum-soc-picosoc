-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_bitbang_cpu_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_bitbang_cpu_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario bitbang_cpu of tb_PicoSoC, from reset (user*, debug
--              unit of the user CPU) : halt and resume of the user CPU
--              through JTAG over the UART pads (debug_mux_sel_i 11), as OpenOCD
--              with the remote_bitbang adapter
--              * dtmcs of the DTM
--              * dmcontrol haltreq : dmstatus allhalted, LED0 no longer
--                follows the switches
--              * dmcontrol resumereq : dmstatus allresumeack and allrunning,
--                LED0 follows the switches again
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere UART pads to JTAG over the UART with
--                               debug_mux_sel_i (was the switch MSBs) :
--                               switches 0x1A, 0x25
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum;
use     asylum.WardRV_debug_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;
use     work.tb_PicoSoC_bitbang_pkg.all;

package tb_PicoSoC_bitbang_cpu_pkg is

  -- Halt and resume of the user CPU
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   bitbang  : in    t_bitbang_rsp
    );

end package tb_PicoSoC_bitbang_cpu_pkg;

package body tb_PicoSoC_bitbang_cpu_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   uart_rx  : inout std_logic
    ;signal   bitbang  : in    t_bitbang_rsp
    ) is
    constant C_TAP       : natural := cfg.jtag.user;
    constant C_SW1       : std_logic_vector(8-1 downto 0) := x"1A";
    constant C_SW2       : std_logic_vector(8-1 downto 0) := x"25";
    -- The halted CPU does nothing during C_HALTED cycles
    constant C_HALTED    : positive := 2000*cfg.clk_ratio;
    variable v_data      : std_logic_vector(32-1 downto 0);

    -- DMI access of the user CPU debugger
    procedure dmi
      (constant op     : in  std_logic_vector(2-1 downto 0)
      ;constant addr   : in  std_logic_vector(DMI_ABITS-1 downto 0)
      ;constant wdata  : in  std_logic_vector(32-1 downto 0)
      ;variable rdata  : out std_logic_vector(32-1 downto 0)
      ) is
    begin
      bitbang_dmi(op, addr, wdata, rdata, cfg, C_TAP, uart_rx, bitbang);
    end procedure;

  begin
    log(ID_SEQUENCER, "bitbang_cpu : halt and resume the user CPU through JTAG over the UART", C_TB_SCOPE);

    set_slv    (C_MUX_BITBANG, clk, mux_sel);
    set_slv    (C_SW1, clk, switch);
    wait_value (led0, C_SW1, cfg, "LED0 = switches 0x" & to_hstring(C_SW1) & " : UART pads to JTAG over the UART");
    bitbang_reset(cfg, uart_rx);

    -- DTM
    bitbang_write_ir(JTAG_IR_DTMCS, "dtmcs", cfg, uart_rx, bitbang, jtag_config(cfg, C_TAP));
    bitbang_scan_dr (x"00000000", v_data, "dtmcs", cfg, uart_rx, bitbang, jtag_config(cfg, C_TAP));
    check_value     (v_data, x"00005071", ERROR, "user CPU dtmcs : idle 5, dmistat 0, abits 7, version 1", C_TB_SCOPE);

    -- Halt
    bitbang_write_ir(JTAG_IR_DMI, "dmi", cfg, uart_rx, bitbang, jtag_config(cfg, C_TAP));
    dmi(DMI_OP_WRITE, DM_DMCONTROL, x"00000001", v_data);                           -- dmactive
    dmi(DMI_OP_WRITE, DM_DMCONTROL, x"80000001", v_data);                           -- haltreq
    for i in 1 to 20 loop
      dmi(DMI_OP_READ, DM_DMSTATUS, x"00000000", v_data);
      exit when v_data(9) = '1';
    end loop;
    check_value(v_data(11 downto 8), "0011", ERROR, "user CPU dmstatus : allhalted", C_TB_SCOPE);
    dmi(DMI_OP_WRITE, DM_DMCONTROL, x"00000001", v_data);

    -- The halted CPU does not copy the switches to LED0
    set_slv     (C_SW2, clk, switch);
    wait_cycles (C_HALTED, clk);
    check_value (led0, C_SW1, ERROR, "user CPU halted : LED0 does not follow the switches", C_TB_SCOPE);

    -- Resume
    dmi(DMI_OP_WRITE, DM_DMCONTROL, x"40000001", v_data);                           -- resumereq
    for i in 1 to 20 loop
      dmi(DMI_OP_READ, DM_DMSTATUS, x"00000000", v_data);
      exit when v_data(17) = '1';
    end loop;
    check_value(v_data(17), '1', ERROR, "user CPU dmstatus.allresumeack", C_TB_SCOPE);
    check_value(v_data(11 downto 8), "1100", ERROR, "user CPU dmstatus : allrunning", C_TB_SCOPE);
    wait_value (led0, C_SW2, cfg, "user CPU resumed : LED0 = switches 0x" & to_hstring(C_SW2));
  end procedure;

end package body tb_PicoSoC_bitbang_cpu_pkg;
