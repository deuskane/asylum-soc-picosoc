-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_tap
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_tap.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Self-checking UVVM testbench of PicoSoC_tap (the injection /
--              status TAP of PicoSoC_top) alone, JTAG BFM of
--              asylum:verification:uvvm on its pins. TCK resynchronized on
--              clk_i by two flip-flops, as in PicoSoC_top. diff_i driven by
--              the scenarios, status_i constant.
--              TESTS_LIST : scenarios of tb_PicoSoC_tap_pkg, separated by
--              ',', each one after a reset pulse ; "" : build only
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
use     asylum.jtag_pkg.all;
use     asylum.string_pkg.all;

library work;
use     work.tb_PicoSoC_tap_pkg.all;

entity tb_PicoSoC_tap is
  generic
    (TESTS_LIST            : string   := ""          -- Scenarios, e.g. "inject,inject_cpu"
    );
end entity tb_PicoSoC_tap;

architecture tb of tb_PicoSoC_tap is
  constant C_SCOPE                 : string  := "TB_PICOSOC_TAP";
  constant C_PERIOD                : time    := 80 ns;

  signal  clk_i                    : std_logic := '0';
  signal  clk_ena                  : boolean   := true;
  signal  arst_b_i                 : std_logic := '0';
  signal  jtag_if                  : t_jtag_if := init_jtag_if_signals;
  signal  tck_r                    : std_logic_vector(2-1 downto 0);
  signal  jtag_ini                 : jtag_ini_t;
  signal  jtag_tgt                 : jtag_tgt_t;
  signal  diff_i                   : std_logic_vector(3-1 downto 0) := (others => '0');
  signal  status_i                 : std_logic_vector(8-1 downto 0) := x"A5";
  signal  inject_error_o           : std_logic_vector(3-1 downto 0);
  signal  inject_cpu_o             : std_logic_vector(9-1 downto 0);
  signal  count                    : t_count := (pulses => (others => 0), cycles => (others => 0));

begin  -- architecture tb

  clock_generator(clk_i, clk_ena, C_PERIOD, "TB Clock");

  -- TCK resynchronized on clk_i (PicoSoC_top), TDO of the TAP when enabled
  process (clk_i, arst_b_i) is
  begin
    if arst_b_i = '0'
    then
      tck_r <= (others => '0');
    elsif rising_edge(clk_i)
    then
      tck_r <= tck_r(0) & jtag_if.tck;
    end if;
  end process;

  jtag_ini    <= (tck => tck_r(1), trst_n => '1', tms => jtag_if.tms, tdi => jtag_if.tdi);
  jtag_if.tdo <= jtag_tgt.tdo when jtag_tgt.tdo_en = '1' else 'Z';

  dut : entity asylum.PicoSoC_tap
    port map
    (clk_i            => clk_i
    ,arst_b_i         => arst_b_i
    ,jtag_ini_i       => jtag_ini
    ,jtag_tgt_o       => jtag_tgt
    ,diff_i           => diff_i
    ,status_i         => status_i
    ,inject_error_o   => inject_error_o
    ,inject_cpu_o     => inject_cpu_o
    );

  -- Pulses and clk_i cycles at 1 of each bit of inject_cpu_o
  p_count : process (clk_i) is
    variable v_last  : std_logic_vector(9-1 downto 0) := (others => '0');
    variable v_count : t_count := (pulses => (others => 0), cycles => (others => 0));
  begin
    if rising_edge(clk_i)
    then
      for j in 0 to 9-1 loop
        if inject_cpu_o(j) = '1'
        then
          v_count.cycles(j) := v_count.cycles(j) + 1;
          if v_last(j) = '0'
          then
            v_count.pulses(j) := v_count.pulses(j) + 1;
          end if;
        end if;
      end loop;
      v_last := inject_cpu_o;
      count  <= v_count;
    end if;
  end process p_count;

  p_sequencer : process
  begin
    log(ID_LOG_HDR, "tb_PicoSoC_tap, TESTS_LIST : " & TESTS_LIST, C_SCOPE);
    for i in 1 to list_length(TESTS_LIST) loop
      if not list_contains(C_TAP_TESTS, list_item(TESTS_LIST, i))
      then
        alert(TB_ERROR, "Unknown test """ & list_item(TESTS_LIST, i) & """ (tests : " & C_TAP_TESTS & ")", C_SCOPE);
      end if;
    end loop;

    for i in 1 to list_length(TESTS_LIST) loop
      jtag_if  <= init_jtag_if_signals;
      diff_i   <= (others => '0');
      arst_b_i <= '0';
      wait for 10*C_PERIOD;
      wait until falling_edge(clk_i);
      arst_b_i <= '1';
      log(ID_LOG_HDR, "TEST " & integer'image(i) & "/" & integer'image(list_length(TESTS_LIST)) & " : " & list_item(TESTS_LIST, i), C_SCOPE);
      run_test(list_item(TESTS_LIST, i), clk_i, jtag_if, diff_i, inject_error_o, count);
    end loop;

    report_alert_counters(FINAL);
    std.env.stop;
    wait;
  end process p_sequencer;

end architecture tb;
