-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_jtag_cpu_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_jtag_cpu_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenarios jtag_cpu_user and jtag_cpu_supervisor of
--              tb_PicoSoC, from reset (firmware user*, WardRV_fsm,
--              USER_CPU_DEBUG_ENABLE or SUPERVISOR_CPU_DEBUG_ENABLE) : the
--              debugger (WardRV_debug) of a CPU, in the JTAG chain of the
--              UART pads (debug_mux_sel_i 10), halts and resumes the hart
--              * dtmcs : version 1, abits 7, idle 5
--              * dmcontrol.dmactive, dmstatus : running, havereset
--                acknowledged
--              * dmcontrol.haltreq : dmstatus allhalted
--              * jtag_cpu_user : while the user CPU is halted, LED0 does not
--                follow the switches ; after the resume it does again ; no
--                difference between the redundant copies of the CPU (the
--                debug requests reach every copy) : led_diff_o stays 0
--              * jtag_cpu_supervisor : while the supervisor CPU is halted,
--                an error (inject_error_i, fault injection) is not handled
--                (led_diff_o = 0) ; after the resume, the supervisor resets
--                the user SoC and counts the error
--              * dmcontrol.resumereq : dmstatus allresumeack, allrunning
--              * dmcontrol.ndmreset : reset of the SoC of the CPU (user SoC ;
--                supervisor SoC, which holds the user SoC in reset) : LED0
--                = 0 ; with the injection / status TAP, the reset bits of
--                the status TDR ; after ndmreset, the firmware runs again
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-22  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere Target TAP with the chain fields of the BFM
--                               (jtag_config(cfg, tap))
-- 2026-11-23  1.2      mrosiere UART pads to JTAG with debug_mux_sel_i (was
--                               the switch MSBs) : switches 0x1A, 0x25
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;

library asylum;
use     asylum.WardRV_debug_pkg.all;

library asylum;
use     asylum.PicoSoC_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;

package tb_PicoSoC_jtag_cpu_pkg is

  -- Halt and resume the user CPU (supervisor = false) or the supervisor CPU
  procedure run
    (constant cfg        : in    t_tb_cfg
    ;constant supervisor : in    boolean
    ;signal   clk        : in    std_logic
    ;signal   switch     : out   std_logic_vector
    ;signal   mux_sel    : out   std_logic_vector
    ;signal   inject     : out   std_logic_vector
    ;signal   led0       : in    std_logic_vector
    ;signal   led_diff   : in    std_logic_vector
    ;signal   jtag_if    : inout t_jtag_if
    );

end package tb_PicoSoC_jtag_cpu_pkg;

package body tb_PicoSoC_jtag_cpu_pkg is

  procedure run
    (constant cfg        : in    t_tb_cfg
    ;constant supervisor : in    boolean
    ;signal   clk        : in    std_logic
    ;signal   switch     : out   std_logic_vector
    ;signal   mux_sel    : out   std_logic_vector
    ;signal   inject     : out   std_logic_vector
    ;signal   led0       : in    std_logic_vector
    ;signal   led_diff   : in    std_logic_vector
    ;signal   jtag_if    : inout t_jtag_if
    ) is
    -- Name and TAP position of the CPU
    function cpu_name return string is
    begin
      if supervisor then return "supervisor CPU"; else return "user CPU"; end if;
    end function;
    function cpu_tap return natural is
    begin
      if supervisor then return cfg.jtag.supervisor; else return cfg.jtag.user; end if;
    end function;
    constant C_NAME      : string  := cpu_name;
    constant C_TAP       : natural := cpu_tap;
    constant C_SW1       : std_logic_vector(8-1 downto 0) := x"1A";
    constant C_SW2       : std_logic_vector(8-1 downto 0) := x"25";
    -- The halted CPU does nothing during C_HALTED cycles
    constant C_HALTED    : positive := 2000*cfg.clk_ratio;
    variable v_data      : std_logic_vector(32-1 downto 0);
    variable v_status    : std_logic_vector(2+8+3+8+8-1 downto 0) := (others => '0');
    variable v_resets    : std_logic_vector(2-1 downto 0);
    variable v_sw        : std_logic_vector(8-1 downto 0);
  begin
    log(ID_SEQUENCER, "jtag_cpu : halt and resume the " & C_NAME & " through its debugger", C_TB_SCOPE);

    set_slv    (C_MUX_JTAG, clk, mux_sel);
    set_slv    (C_SW1, clk, switch);
    wait_value (led0, C_SW1, cfg, "LED0 = switches 0x" & to_hstring(C_SW1) & " : UART pads to JTAG");
    chain_reset(cfg, jtag_if);

    -- DTM and Debug Module
    dtmcs_scan (cfg, C_TAP, x"00000000", v_data, jtag_if);
    check_value(v_data, x"00005071", ERROR, C_NAME & " dtmcs : idle 5, dmistat 0, abits 7, version 1", C_TB_SCOPE);
    dmi_write  (cfg, C_TAP, DM_DMCONTROL, x"00000001", jtag_if);                    -- dmactive
    dmi_read   (cfg, C_TAP, DM_DMSTATUS , v_data, jtag_if);
    check_value(v_data(11 downto 8), "1100", ERROR, C_NAME & " dmstatus : running", C_TB_SCOPE);
    dmi_write  (cfg, C_TAP, DM_DMCONTROL, x"10000001", jtag_if);                    -- ackhavereset
    dmi_read   (cfg, C_TAP, DM_DMSTATUS , v_data, jtag_if);
    check_value(v_data(19 downto 18), "00", ERROR, C_NAME & " dmstatus.havereset acknowledged", C_TB_SCOPE);

    -- Halt
    dmi_write  (cfg, C_TAP, DM_DMCONTROL, x"80000001", jtag_if);                    -- haltreq
    for i in 1 to 50 loop
      dmi_read (cfg, C_TAP, DM_DMSTATUS, v_data, jtag_if);
      exit when v_data(9) = '1';
    end loop;
    check_value(v_data(11 downto 8), "0011", ERROR, C_NAME & " dmstatus : allhalted", C_TB_SCOPE);
    dmi_write  (cfg, C_TAP, DM_DMCONTROL, x"00000001", jtag_if);

    if not supervisor
    then
      -- The user CPU does not copy the switches to LED0
      set_slv     (C_SW2, clk, switch);
      wait_cycles (C_HALTED, clk);
      check_value (led0, C_SW1, ERROR, "user CPU halted : LED0 does not follow the switches", C_TB_SCOPE);
    elsif cfg.fault
    then
      -- The supervisor CPU does not handle an error
      inject_error(0, cfg, clk, inject);
      wait_cycles (C_HALTED, clk);
      check_value (led_diff, "000", ERROR, "supervisor CPU halted : the error is not handled (led_diff = 0)", C_TB_SCOPE);
    end if;

    -- Resume
    dmi_write  (cfg, C_TAP, DM_DMCONTROL, x"40000001", jtag_if);                    -- resumereq
    for i in 1 to 50 loop
      dmi_read (cfg, C_TAP, DM_DMSTATUS, v_data, jtag_if);
      exit when v_data(17) = '1';
    end loop;
    check_value(v_data(17), '1', ERROR, C_NAME & " dmstatus.allresumeack", C_TB_SCOPE);
    check_value(v_data(11 downto 8), "1100", ERROR, C_NAME & " dmstatus : allrunning", C_TB_SCOPE);

    if not supervisor
    then
      wait_value  (led0, C_SW2, cfg, "user CPU resumed : LED0 = switches 0x" & to_hstring(C_SW2));
      wait_cycles (C_HALTED, clk);
      check_stable(led_diff, C_HALTED*cfg.clk_period, ERROR, "no difference between the copies of the user CPU after the halt", C_TB_SCOPE);
      check_value (led_diff, "000", ERROR, "led_diff = 0 : the copies of the user CPU were halted together", C_TB_SCOPE);
    elsif cfg.fault
    then
      wait_value  (led_diff, "001", cfg, "supervisor CPU resumed : the error is handled (led_diff = 1)");
      wait_value  (led0, C_SW1, cfg, "the firmware of the user SoC runs again after its reset");
    end if;

    -- ndmreset : reset of the SoC of the CPU (and of the user SoC)
    dmi_write (cfg, C_TAP, DM_DMCONTROL, x"00000003", jtag_if);                     -- ndmreset, dmactive
    wait_value(led0, x"00", cfg, C_NAME & " ndmreset : user SoC in reset (LED0 = 0)");
    if cfg.jtag.inject >= 0
    then
      -- Reset bits of the status TDR (MSBs) : supervisor SoC, user SoC
      jtag_write_ir(ir_value => PICOSOC_JTAG_IR_STATUS, msg => "STATUS", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, cfg.jtag.inject));
      v_resets := "00" when supervisor else "10";
      jtag_scan_dr (data_value => v_status, data_out => v_status, msg => "STATUS", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, cfg.jtag.inject));
      check_value(v_status(v_status'high downto v_status'high-1), v_resets, ERROR,
                  C_NAME & " ndmreset : reset bits of the status TDR (supervisor SoC, user SoC)", C_TB_SCOPE);
    end if;
    dmi_write (cfg, C_TAP, DM_DMCONTROL, x"00000001", jtag_if);
    v_sw := C_SW1 when supervisor else C_SW2;
    wait_value(led0, v_sw, cfg, C_NAME & " ndmreset released : the firmware runs again (LED0 = switches)");
  end procedure;

end package body tb_PicoSoC_jtag_cpu_pkg;
