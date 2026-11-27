-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_jtag_inject_cpu_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_jtag_inject_cpu_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario jtag_inject_cpu of tb_PicoSoC, from reset (firmware
--              user*, DEBUG_ENABLE) : the injection inside the CPUs, bits
--              [6:4], [10:8], [14:12] (CPU copy 0, 1, 2) of INJECT of the
--              injection / status TAP (JTAG on the UART pads,
--              debug_mux_sel_i 10), in the whole SoC :
--              * for each copy i : INJECT written with its 3 bits, then 0 :
--                the capture reads diff (000) in [2:0], 0 in [15:3]
--              * with fault injection, the HWLA (armed before) is triggered
--                by the pulses of the copy 0 (flags of STATUS)
--              * [2:0] stayed 0 : no error injected outside the CPUs, and
--                the reference CPUs do not use inject_i : no difference
--                flag, the firmware still runs (LED0 follows new switches)
--              The pulses themselves (one SoC clock cycle per 0 -> 1, on the
--              bit of the copy) are checked on PicoSoC_tap by tb_PicoSoC_tap
--              (scenario inject_cpu) : GHDL 6.0.0 crashes at the elaboration
--              of an external name to inject_cpu_i of cpu_safety
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-27  1.0      mrosiere Created
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

package tb_PicoSoC_jtag_inject_cpu_pkg is

  -- INJECT inside the CPUs in the whole SoC : no side effect on the reference CPUs
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    );

end package tb_PicoSoC_jtag_inject_cpu_pkg;

package body tb_PicoSoC_jtag_inject_cpu_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    constant C_SW1     : std_logic_vector(8-1 downto 0) := x"2D";
    constant C_SW2     : std_logic_vector(8-1 downto 0) := x"0B";
    constant C_TAP     : natural  := cfg.jtag.inject;
    variable v_read    : std_logic_vector(16-1 downto 0);
    variable v_write   : std_logic_vector(16-1 downto 0);

    -- Flags of the HWLA in STATUS (from the LSB : arm, armed, triggered,
    -- sending), above the resets, switches, led_diff, LED1 and LED0
    constant C_ARMED   : std_logic_vector(4-1 downto 0) := "0011";
    variable v_status  : std_logic_vector(4+2+8+3+8+8-1 downto 0);

    -- STATUS scans until the flags of the HWLA are (eq) or are no longer
    -- (not eq) C_ARMED, at most 100 scans ; returns the flags
    procedure read_hwla
      (constant eq     : in  boolean
      ;variable flags  : out std_logic_vector(4-1 downto 0)
      ) is
    begin
      jtag_write_ir(ir_value => PICOSOC_JTAG_IR_STATUS, msg => "STATUS", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
      for i in 1 to 100 loop
        jtag_scan_dr(data_value => (v_status'range => '0'), data_out => v_status, msg => "STATUS", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
        exit when (v_status(v_status'high downto v_status'high-3) = C_ARMED) = eq;
      end loop;
      flags := v_status(v_status'high downto v_status'high-3);
      jtag_write_ir(ir_value => PICOSOC_JTAG_IR_INJECT, msg => "INJECT", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
    end procedure;

    variable v_flags   : std_logic_vector(4-1 downto 0);
  begin
    log(ID_SEQUENCER, "jtag_inject_cpu : injection inside the CPUs, INJECT [6:4], [10:8], [14:12]", C_TB_SCOPE);

    set_slv    (C_MUX_JTAG, clk, mux_sel);
    set_slv    (C_SW1, clk, switch);
    wait_value (led0, C_SW1, cfg, "LED0 = switches 0x" & to_hstring(C_SW1) & " : UART pads to JTAG");
    chain_reset(cfg, jtag_if);
    read_hwla(true, v_flags);
    check_value(v_flags, C_ARMED, ERROR, "HWLA armed before the injection inside the CPUs", C_TB_SCOPE);

    for i in 0 to 3-1 loop
      v_write                     := (others => '0');
      v_write(4+4*i+2 downto 4+4*i) := "111";
      jtag_scan_dr(data_value => v_write, data_out => v_read, msg => "INJECT : CPU copy " & integer'image(i) & ", 3 bits", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
      check_value (v_read, x"0000", ERROR, "INJECT reads diff 000 in [2:0], 0 in [15:3] (before copy " & integer'image(i) & ")", C_TB_SCOPE);
      jtag_scan_dr(data_value => x"0000", data_out => v_read, msg => "INJECT 0", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
      check_value (v_read, x"0000", ERROR, "INJECT reads diff 000 in [2:0], 0 in [15:3] (after copy " & integer'image(i) & ")", C_TB_SCOPE);
      -- The pulses of the copy 0 trigger the HWLA (with fault injection)
      if i = 0 and cfg.fault
      then
        read_hwla(false, v_flags);
        check_value(v_flags(2), '1', ERROR, "HWLA triggered by the injection inside the CPU copy 0 (flags " & to_string(v_flags) & ")", C_TB_SCOPE);
      end if;
    end loop;

    -- No error outside the CPUs : no difference flag, the firmware runs
    check_value(led_diff, "000", ERROR, "led_diff : no difference flag ([2:0] stayed 0)", C_TB_SCOPE);
    set_slv    (C_SW2, clk, switch);
    wait_value (led0, C_SW2, cfg, "LED0 = switches 0x" & to_hstring(C_SW2) & " : the firmware runs (the reference CPUs do not use inject_i)");
  end procedure;

end package body tb_PicoSoC_jtag_inject_cpu_pkg;
