-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_bitbang_inject_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_bitbang_inject_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario bitbang_inject of tb_PicoSoC, from reset (user*,
--              DEBUG_ENABLE, supervisor, lock-step, fault injection) : the
--              INJECT register of the injection / status TAP written and
--              read back through JTAG over the UART pads (debug_mux_sel_i 11)
--              * diff read 000 before the injection
--              * an error injected in CPU1 : the supervisor resets the user
--                SoC ; diff, read while the injection lasts, is CPU0 vs
--                CPU1 (001)
--              * injection stopped : the firmware runs again, diff 000
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere UART pads to JTAG over the UART with
--                               debug_mux_sel_i (was the switch MSBs) :
--                               switches 0x1A
-- 2026-11-24  1.2      mrosiere remote_bitbang BFM rbb_bfm_pkg (rbb_if, answers
--                               t_rbb_answers)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum_uvvm;
use     asylum_uvvm.rbb_bfm_pkg.all;

library asylum;
use     asylum.PicoSoC_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;
use     work.tb_PicoSoC_bitbang_pkg.all;

package tb_PicoSoC_bitbang_inject_pkg is

  -- Error injected in CPU1 through the INJECT register
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   rbb_if   : inout t_rbb_if
    ;signal   bitbang  : in    t_rbb_answers
    );

end package tb_PicoSoC_bitbang_inject_pkg;

package body tb_PicoSoC_bitbang_inject_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   rbb_if   : inout t_rbb_if
    ;signal   bitbang  : in    t_rbb_answers
    ) is
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"1A";
    constant C_TAP     : natural  := cfg.jtag.inject;
    -- No more change during C_SETTLE cycles
    constant C_SETTLE  : positive := 2000*cfg.clk_ratio;
    variable v_read    : std_logic_vector(16-1 downto 0);  -- INJECT : diff in [2:0]
  begin
    log(ID_SEQUENCER, "bitbang_inject : error injected in CPU1 through JTAG over the UART", C_TB_SCOPE);

    set_slv    (C_MUX_BITBANG, clk, mux_sel);
    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches 0x" & to_hstring(C_SW) & " : UART pads to JTAG over the UART");
    check_value(led_diff, "000", ERROR, "led_diff : no difference before the injection", C_TB_SCOPE);

    bitbang_reset   (cfg, clk, rbb_if);
    bitbang_write_ir(PICOSOC_JTAG_IR_INJECT, "INJECT", cfg, clk, rbb_if, bitbang, jtag_config(cfg, C_TAP));
    bitbang_scan_dr ("0000000000000010", v_read, "inject an error in CPU1", cfg, clk, rbb_if, bitbang, jtag_config(cfg, C_TAP));
    check_value     (v_read, "0000000000000000", ERROR, "diff read through JTAG over the UART before the injection", C_TB_SCOPE);

    wait_value(led0, x"00", cfg, "the supervisor resets the user SoC (LED0 = 0)");

    -- diff, cleared by each reset of the user SoC, read while the injection
    -- lasts
    for i in 1 to 20 loop
      bitbang_scan_dr("0000000000000010", v_read, "keep the injection, read diff", cfg, clk, rbb_if, bitbang, jtag_config(cfg, C_TAP));
      exit when v_read /= "0000000000000000";
    end loop;
    check_value(v_read, "0000000000000001", ERROR, "diff read through JTAG over the UART during the injection : CPU0 vs CPU1", C_TB_SCOPE);

    bitbang_scan_dr("0000000000000000", v_read, "stop the injection", cfg, clk, rbb_if, bitbang, jtag_config(cfg, C_TAP));
    wait_value     (led0, C_SW, cfg, "the firmware runs again (LED0 = switches)");
    wait_cycles    (C_SETTLE, clk);
    bitbang_scan_dr("0000000000000000", v_read, "read diff", cfg, clk, rbb_if, bitbang, jtag_config(cfg, C_TAP));
    check_value    (v_read, "0000000000000000", ERROR, "diff read through JTAG over the UART after the injection", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_bitbang_inject_pkg;
