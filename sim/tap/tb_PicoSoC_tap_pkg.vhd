-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_tap_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_tap_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenarios of tb_PicoSoC_tap (INJECT of the injection / status
--              TAP, PicoSoC_tap alone), names and dispatch :
--              * inject : [2:0] (outside the CPUs) : a write of 1 sets the
--                level of its copy on inject_error_o (synchronized) until a
--                write of 0 ; no pulse on inject_cpu_o ; the capture reads
--                diff_i in [2:0], 0 in [15:3]
--              * inject_cpu : [6:4], [10:8], [14:12] (inside the CPU copy 0,
--                1, 2) : for each copy i and bit k, a write of the bit
--                4+4*i+k alone gives exactly one pulse of one clk_i cycle on
--                inject_cpu_o(3*i+k), none on the other bits nor on
--                inject_error_o ; the same value written again (no 0 -> 1)
--                and 0 give no pulse ; the 9 bits together : one pulse on
--                each ; the reserved bits [3], [7], [11], [15] : no pulse
--              Pulses counted by tb_PicoSoC_tap (t_count) : rising edges
--              and clk_i cycles at 1 of each bit of inject_cpu_o
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
use     asylum.string_pkg.all;

package tb_PicoSoC_tap_pkg is

  constant C_TB_TAP_SCOPE : string := "TB_PICOSOC_TAP";

  -- Names of the scenarios (valid items of TESTS_LIST)
  constant C_TAP_TESTS    : string := "inject,inject_cpu";

  type t_naturals9 is array (0 to 9-1) of natural;
  type t_count is record
    pulses     : t_naturals9;   -- rising edges of inject_cpu_o(j)
    cycles     : t_naturals9;   -- clk_i cycles with inject_cpu_o(j) at 1
  end record t_count;

  -- BFM configuration of the TAP alone : TCK 1 us (slow against clk_i)
  function tap_config return t_jtag_bfm_config;

  procedure run_test
    (constant name       : in    string
    ;signal   clk        : in    std_logic
    ;signal   jtag_if    : inout t_jtag_if
    ;signal   diff       : out   std_logic_vector
    ;signal   inject     : in    std_logic_vector
    ;signal   count      : in    t_count
    );

end package tb_PicoSoC_tap_pkg;

package body tb_PicoSoC_tap_pkg is

  function tap_config return t_jtag_bfm_config is
    variable v_config : t_jtag_bfm_config := C_JTAG_BFM_CONFIG_DEFAULT;
  begin
    v_config.tck_period  := 1 us;
    v_config.ir_width    := PICOSOC_JTAG_IR_WIDTH;
    v_config.trst_enable := false;
    return v_config;
  end function;

  procedure run_test
    (constant name       : in    string
    ;signal   clk        : in    std_logic
    ;signal   jtag_if    : inout t_jtag_if
    ;signal   diff       : out   std_logic_vector
    ;signal   inject     : in    std_logic_vector
    ;signal   count      : in    t_count
    ) is
    -- The outputs follow an Update-DR within a few clk_i cycles
    -- (synchronizers, edge detection)
    constant C_SETTLE  : positive := 20;
    variable v_read    : std_logic_vector(16-1 downto 0);
    variable v_write   : std_logic_vector(16-1 downto 0);
    variable v_before  : t_count;

    -- Write INJECT, wait C_SETTLE cycles
    procedure write_inject
      (constant value  : in    std_logic_vector(16-1 downto 0)
      ;constant msg    : in    string
      ) is
    begin
      v_before := count;
      jtag_scan_dr(data_value => value, data_out => v_read, msg => msg, jtag_if => jtag_if, scope => C_TB_TAP_SCOPE, config => tap_config);
      for c in 1 to C_SETTLE loop
        wait until rising_edge(clk);
      end loop;
    end procedure;

    -- Pulses and cycles at 1 of the bit j of inject_cpu_o since the last
    -- write, pulses of all the bits but j (j = 9 : all of them)
    impure function pulses (j : natural) return natural is
    begin
      return count.pulses(j) - v_before.pulses(j);
    end function;

    impure function cycles (j : natural) return natural is
    begin
      return count.cycles(j) - v_before.cycles(j);
    end function;

    impure function others_pulses (j : natural) return natural is
      variable v_sum : natural := 0;
    begin
      for b in 0 to 9-1 loop
        if b /= j
        then
          v_sum := v_sum + pulses(b);
        end if;
      end loop;
      return v_sum;
    end function;

  begin
    jtag_reset   (msg => "Test-Logic-Reset", jtag_if => jtag_if, scope => C_TB_TAP_SCOPE, config => tap_config);
    jtag_write_ir(ir_value => PICOSOC_JTAG_IR_INJECT, msg => "INJECT", jtag_if => jtag_if, scope => C_TB_TAP_SCOPE, config => tap_config);

    if    string_eq(name, "inject")
    then
      log(ID_SEQUENCER, "inject : [2:0], the injection outside the CPUs (a level)", C_TB_TAP_SCOPE);
      diff <= "101";
      write_inject(x"0002", "INJECT 010");
      check_value(v_read , x"0005", ERROR, "INJECT reads diff_i in [2:0], 0 in [15:3]", C_TB_TAP_SCOPE);
      check_value(inject , "010"  , ERROR, "inject_error_o = 010 after the write", C_TB_TAP_SCOPE);
      check_value(others_pulses(9), 0, ERROR, "no pulse on inject_cpu_o", C_TB_TAP_SCOPE);
      write_inject(x"0000", "INJECT 000");
      check_value(inject , "000"    , ERROR, "inject_error_o = 000 after the write of 0", C_TB_TAP_SCOPE);
    elsif string_eq(name, "inject_cpu")
    then
      log(ID_SEQUENCER, "inject_cpu : [6:4], [10:8], [14:12], the injection inside the CPU copies (a pulse per 0 -> 1)", C_TB_TAP_SCOPE);
      for i in 0 to 3-1 loop
        for k in 0 to 3-1 loop
          v_write          := (others => '0');
          v_write(4+4*i+k) := '1';
          write_inject(v_write, "INJECT : CPU copy " & integer'image(i) & ", bit " & integer'image(k));
          check_value(v_read(15 downto 3), "0000000000000", ERROR, "INJECT reads 0 in [15:3]", C_TB_TAP_SCOPE);
          check_value(pulses(3*i+k), 1, ERROR, "copy " & integer'image(i) & ", bit " & integer'image(k) & " : one pulse on inject_cpu_o(" & integer'image(3*i+k) & ")", C_TB_TAP_SCOPE);
          check_value(cycles(3*i+k), 1, ERROR, "copy " & integer'image(i) & ", bit " & integer'image(k) & " : the pulse lasts one clk_i cycle", C_TB_TAP_SCOPE);
          check_value(others_pulses(3*i+k), 0, ERROR, "copy " & integer'image(i) & ", bit " & integer'image(k) & " : no pulse on the other bits", C_TB_TAP_SCOPE);
          check_value(inject, "000", ERROR, "copy " & integer'image(i) & ", bit " & integer'image(k) & " : inject_error_o stays 000", C_TB_TAP_SCOPE);
          write_inject(v_write, "INJECT : the same value again");
          check_value(others_pulses(9), 0, ERROR, "copy " & integer'image(i) & ", bit " & integer'image(k) & " written again (no 0 -> 1) : no pulse", C_TB_TAP_SCOPE);
          write_inject(x"0000", "INJECT 0");
          check_value(others_pulses(9), 0, ERROR, "INJECT 0 : no pulse", C_TB_TAP_SCOPE);
        end loop;
      end loop;
      write_inject(x"7770", "INJECT : the 9 bits inside the CPUs");
      for j in 0 to 9-1 loop
        check_value(pulses(j), 1, ERROR, "the 9 bits : one pulse on inject_cpu_o(" & integer'image(j) & ")", C_TB_TAP_SCOPE);
      end loop;
      write_inject(x"0000", "INJECT 0");
      write_inject(x"8888", "INJECT : the reserved bits [3], [7], [11], [15]");
      check_value(others_pulses(9), 0, ERROR, "the reserved bits : no pulse", C_TB_TAP_SCOPE);
      check_value(inject, "000", ERROR, "the reserved bits : inject_error_o stays 000", C_TB_TAP_SCOPE);
    else
      alert(TB_ERROR, "Unknown test " & name, C_TB_TAP_SCOPE);
    end if;
  end procedure;

end package body tb_PicoSoC_tap_pkg;
