-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_jtag_inject_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_jtag_inject_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario jtag_inject of tb_PicoSoC, from reset (firmware
--              user*, DEBUG_ENABLE, fault injection, no supervisor or
--              lock-step) : an error injected in CPU1 through the TDR
--              PICOSOC_JTAG_IR_INJECT of the injection TAP (JTAG on the UART
--              pads, debug_mux_sel_i 10) has the effect of the inject_error_i
--              button, and the same TDR reads diff
--              * the scan that starts the injection reads diff = 000
--              * no supervisor : led_diff_o shows the difference flags of
--                CPU1 (lock-step 001, TMR 011) ; the scan that stops the
--                injection reads them ; they stay set (read again)
--              * supervisor : the supervisor resets the user SoC (LED0 = 0)
--                and counts the errors on led_diff_o ; while the injection
--                lasts, a scan reads diff = 001 (polled : each reset clears
--                diff) ; after the injection, the firmware runs again, no
--                more reset, diff = 000
--              CPU1 (written 010) : diff differs from the written value
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-22  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere Target TAP with the chain fields of the BFM
--                               (jtag_config(cfg, tap))
-- 2026-11-23  1.2      mrosiere UART pads to JTAG with debug_mux_sel_i (was
--                               the switch MSBs) : switches 0x1A
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;

library asylum;
use     asylum.PicoSoC_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;

package tb_PicoSoC_jtag_inject_pkg is

  -- Error injected through JTAG, diff read through JTAG
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    );

end package tb_PicoSoC_jtag_inject_pkg;

package body tb_PicoSoC_jtag_inject_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"1A";
    constant C_TAP     : natural  := cfg.jtag.inject;
    -- No more change during C_SETTLE cycles
    constant C_SETTLE  : positive := 2000*cfg.clk_ratio;
    variable v_diff    : std_logic_vector(3-1 downto 0);
    variable v_read    : std_logic_vector(3-1 downto 0);
  begin
    log(ID_SEQUENCER, "jtag_inject : error injected in CPU1 through JTAG", C_TB_SCOPE);

    v_diff := "011" when cfg.tmr else "001";

    set_slv    (C_MUX_JTAG, clk, mux_sel);
    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches 0x" & to_hstring(C_SW) & " : UART pads to JTAG");
    check_value(led_diff, "000", ERROR, "led_diff : no difference before the injection", C_TB_SCOPE);

    chain_reset(cfg, jtag_if);
    jtag_write_ir(ir_value => PICOSOC_JTAG_IR_INJECT, msg => "INJECT", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
    jtag_scan_dr (data_value => "010", data_out => v_read, msg => "inject an error in CPU1", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
    check_value(v_read, "000", ERROR, "diff read through JTAG before the injection", C_TB_SCOPE);

    if not cfg.supervisor
    then
      wait_value  (led_diff, v_diff, cfg, "led_diff : difference flags of CPU1 (injection through JTAG)");
      jtag_scan_dr (data_value => "000", data_out => v_read, msg => "stop the injection", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
      check_value (v_read, v_diff, ERROR, "diff read through JTAG : difference flags of CPU1", C_TB_SCOPE);
      wait_cycles (C_SETTLE, clk);
      check_stable(led_diff, C_SETTLE*cfg.clk_period, ERROR, "led_diff : the flags are sticky", C_TB_SCOPE);
      check_value (led_diff, v_diff, ERROR, "led_diff : difference flags of CPU1", C_TB_SCOPE);
      jtag_scan_dr (data_value => "000", data_out => v_read, msg => "read diff", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
      check_value (v_read, v_diff, ERROR, "diff read through JTAG after the injection : sticky flags", C_TB_SCOPE);
    else
      wait_value(led0, x"00", cfg, "the supervisor resets the user SoC (LED0 = 0)");
      if led_diff = "000"
      then
        wait until led_diff /= "000" for cfg.timeout;
      end if;
      check_value(led_diff /= "000", ERROR, "led_diff : the supervisor counts the errors", C_TB_SCOPE);

      -- diff, cleared by each reset of the user SoC, read while the
      -- injection lasts
      for i in 1 to 20 loop
        jtag_scan_dr (data_value => "010", data_out => v_read, msg => "keep the injection, read diff", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
        exit when v_read /= "000";
      end loop;
      check_value(v_read, "001", ERROR, "diff read through JTAG during the injection : CPU0 vs CPU1", C_TB_SCOPE);

      jtag_scan_dr (data_value => "000", data_out => v_read, msg => "stop the injection", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
      wait_value  (led0, C_SW, cfg, "the firmware runs again (LED0 = switches)");
      wait_cycles (C_SETTLE, clk);
      check_stable(led_diff, C_SETTLE*cfg.clk_period, ERROR, "led_diff : no more error after the injection", C_TB_SCOPE);
      check_stable(led0    , C_SETTLE*cfg.clk_period, ERROR, "LED0 : no more reset after the injection", C_TB_SCOPE);
      jtag_scan_dr (data_value => "000", data_out => v_read, msg => "read diff", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
      check_value (v_read, "000", ERROR, "diff read through JTAG after the injection", C_TB_SCOPE);
    end if;
  end procedure;

end package body tb_PicoSoC_jtag_inject_pkg;
