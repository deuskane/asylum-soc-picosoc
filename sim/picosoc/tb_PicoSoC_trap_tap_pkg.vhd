-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_trap_tap_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_trap_tap_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario trap_tap of tb_PicoSoC, from reset (firmware user*,
--              no safety : no difference flag, fault injection,
--              DEBUG_ENABLE, USER_CPU_DEBUG_ENABLE) : without compare, only
--              a 1 -> 0 of the request of the TAP clears a trap
--              * a request of one SoC clock cycle on inject_error_i(0) : the
--                trap flips the instruction bit of CPU0 : the firmware stops
--                (LED0 does not follow the switches)
--              * ndmreset of the user CPU debugger (reset of the user SoC) :
--                the trap stays, the firmware does not run
--              * INJECT written 001 then 000 : the 1 -> 0 clears the trap ;
--                after a new ndmreset the firmware runs again
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-26  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;

library asylum;
use     asylum.WardRV_debug_pkg.all;
use     asylum.PicoSoC_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;

package tb_PicoSoC_trap_tap_pkg is

  -- Trap without difference flag, cleared by the TAP
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    );

end package tb_PicoSoC_trap_tap_pkg;

package body tb_PicoSoC_trap_tap_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    constant C_CPU_TAP : natural  := cfg.jtag.user;
    constant C_TAP     : natural  := cfg.jtag.inject;
    constant C_SW1     : std_logic_vector(8-1 downto 0) := x"5A";
    constant C_SW2     : std_logic_vector(8-1 downto 0) := x"A6";
    -- The stopped firmware does not copy the switches during C_SETTLE cycles
    constant C_SETTLE  : positive := 2000*cfg.clk_ratio;
    variable v_read    : std_logic_vector(3-1 downto 0);

    -- ndmreset pulse of the user CPU debugger : reset of the user SoC
    procedure user_reset
      (constant msg  : in    string
      ;signal   jif  : inout t_jtag_if
      ) is
    begin
      dmi_write (cfg, C_CPU_TAP, DM_DMCONTROL, x"00000003", jif);                       -- ndmreset, dmactive
      wait_value(led0, x"00", cfg, msg & " : user SoC in reset (LED0 = 0)");
      dmi_write (cfg, C_CPU_TAP, DM_DMCONTROL, x"00000001", jif);
    end procedure;
  begin
    log(ID_SEQUENCER, "trap_tap : no difference flag, the trap is cleared by the TAP (1 -> 0)", C_TB_SCOPE);

    set_slv    (C_MUX_JTAG, clk, mux_sel);
    set_slv    (C_SW1, clk, switch);
    wait_value (led0, C_SW1, cfg, "LED0 = switches 0x" & to_hstring(C_SW1) & " : UART pads to JTAG");
    chain_reset(cfg, jtag_if);
    dmi_write  (cfg, C_CPU_TAP, DM_DMCONTROL, x"00000001", jtag_if);                    -- dmactive

    -- Request of one SoC clock cycle : CPU0 trapped, the firmware stops
    log(ID_SEQUENCER_SUB, "Request of one SoC clock cycle in CPU0", C_TB_SCOPE);
    wait until falling_edge(clk);
    inject(0) <= cfg.fault_on;
    for c in 1 to cfg.clk_ratio loop
      wait until falling_edge(clk);
    end loop;
    inject(0) <= not cfg.fault_on;
    set_slv    (C_SW2, clk, switch);
    wait_cycles(C_SETTLE, clk);
    check_value(led0, C_SW1, ERROR, "trap : the firmware stops (LED0 does not follow the switches)", C_TB_SCOPE);

    -- Reset of the user SoC : the trap stays
    user_reset ("ndmreset with the trap", jtag_if);
    wait_cycles(C_SETTLE, clk);
    check_value(led0, x"00", ERROR, "the trap survives the reset of the user SoC : the firmware does not run (LED0 = 0)", C_TB_SCOPE);

    -- INJECT 1 then 0 : the 1 -> 0 clears the trap
    jtag_write_ir(ir_value => PICOSOC_JTAG_IR_INJECT, msg => "INJECT", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
    jtag_scan_dr (data_value => "001", data_out => v_read, msg => "INJECT CPU0", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
    jtag_scan_dr (data_value => "000", data_out => v_read, msg => "INJECT 0 : clear the trap", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
    check_value  (v_read, "000", ERROR, "diff read through JTAG : no compare, no flag", C_TB_SCOPE);
    user_reset   ("ndmreset after the clear", jtag_if);
    wait_value   (led0, C_SW2, cfg, "trap cleared by the TAP : the firmware runs again (LED0 = switches)");
    check_value  (led_diff, "000", ERROR, "led_diff : no difference flag without safety", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_trap_tap_pkg;
