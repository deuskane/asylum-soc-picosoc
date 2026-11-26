-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_trap_reset_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_trap_reset_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario trap_reset of tb_PicoSoC, from reset (firmware
--              user*, supervisor, lock-step, fault injection,
--              SUPERVISOR_CPU_DEBUG_ENABLE) : a trap set while the supervisor
--              holds the user SoC in reset survives this reset
--              * ndmreset of the supervisor debugger : the supervisor SoC in
--                reset holds the user SoC in reset (LED0 = 0)
--              * a request of one SoC clock cycle in CPU1 : its trap waits
--                (no instruction fetched, no difference flag)
--              * ndmreset released : the supervisor releases the user SoC,
--                CPU1 runs with the error, the compare flags it, the
--                supervisor resets the user SoC once (led_diff_o = 1), the
--                trap is cleared : no other reset
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

package tb_PicoSoC_trap_reset_pkg is

  -- Trap set during the reset of the user SoC by the supervisor
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

end package tb_PicoSoC_trap_reset_pkg;

package body tb_PicoSoC_trap_reset_pkg is

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
    constant C_TAP     : natural  := cfg.jtag.supervisor;
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"3C";
    -- The user SoC held in reset, then no other reset, during C_SETTLE cycles
    constant C_SETTLE  : positive := 2000*cfg.clk_ratio;
  begin
    log(ID_SEQUENCER, "trap_reset : a trap set while the supervisor holds the user SoC in reset", C_TB_SCOPE);

    set_slv    (C_MUX_JTAG, clk, mux_sel);
    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches 0x" & to_hstring(C_SW) & " : UART pads to JTAG");
    chain_reset(cfg, jtag_if);

    -- Supervisor SoC in reset (ndmreset) : the user SoC is held in reset
    dmi_write  (cfg, C_TAP, DM_DMCONTROL, x"00000001", jtag_if);                    -- dmactive
    dmi_write  (cfg, C_TAP, DM_DMCONTROL, x"00000003", jtag_if);                    -- ndmreset, dmactive
    wait_value (led0, x"00", cfg, "supervisor ndmreset : user SoC in reset (LED0 = 0)");

    -- Request of one SoC clock cycle in CPU1 : the trap waits
    log(ID_SEQUENCER_SUB, "Request of one SoC clock cycle in CPU1, user SoC in reset", C_TB_SCOPE);
    wait until falling_edge(clk);
    inject(1) <= cfg.fault_on;
    for c in 1 to cfg.clk_ratio loop
      wait until falling_edge(clk);
    end loop;
    inject(1) <= not cfg.fault_on;
    wait_cycles (C_SETTLE, clk);
    check_value (led0    , x"00", ERROR, "user SoC still in reset (LED0 = 0)", C_TB_SCOPE);
    check_value (led_diff, "000" , ERROR, "no difference while the user SoC is in reset", C_TB_SCOPE);

    -- ndmreset released : the trapped error is seen once
    dmi_write   (cfg, C_TAP, DM_DMCONTROL, x"00000001", jtag_if);
    wait_value  (led_diff, "001", cfg, "user SoC released : the trapped error in CPU1 is flagged, one reset (led_diff = 1)");
    wait_value  (led0    , C_SW , cfg, "the firmware runs again (LED0 = switches)");
    wait_cycles (C_SETTLE, clk);
    check_stable(led0    , C_SETTLE*cfg.clk_period, ERROR, "trap cleared : LED0 stable", C_TB_SCOPE);
    check_value (led_diff, "001", ERROR, "trap cleared : one reset", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_trap_reset_pkg;
