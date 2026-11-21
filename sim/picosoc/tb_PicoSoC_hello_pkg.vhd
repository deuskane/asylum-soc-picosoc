-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_hello_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_hello_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario hello of tb_PicoSoC, from reset (firmware hello,
--              USER_NB_CPU CPUs) : under the spinlock, each CPU prints
--              "CPU II - Loop CCCCCCCC" (II : mhartid, CCCCCCCC : shared loop
--              counter in RAM2), increments the counter (on LED0) and sets
--              its bit in LED1.
--              * the counter of the lines goes 0, 1, 2, ... (mutual
--                exclusion, one shared counter), the CPU ids are valid
--              * every CPU takes the lock (LED1 = all CPUs) and the counter
--                progresses (LED0 >= 4 x USER_NB_CPU) : no deadlock, no
--                starvation
--              * led_diff_o stays 0 : with lock-step / TMR, the redundant
--                CPUs of each cluster read the same mhartid and stay equal
--                (no difference flag, no error counted by the supervisor)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-20  1.0      mrosiere Created (split of tb_PicoSoC)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_hello_pkg is

  -- Every CPU takes the spinlock in turn
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_hello_pkg;

package body tb_PicoSoC_hello_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    ) is
    constant C_NB_LINE : positive := 4*cfg.nb_cpu;
    constant C_ALL_CPU : std_logic_vector(led1'length-1 downto 0) :=
      std_logic_vector(to_unsigned(2**cfg.nb_cpu-1, led1'length));
    variable v_line    : string(1 to 128);
    variable v_len     : natural;
    variable v_ok      : boolean;
    variable v_start   : time;
  begin
    v_start := now;
    log(ID_SEQUENCER, "hello : " & integer'image(cfg.nb_cpu) & " CPUs share the spinlock and the loop counter", C_TB_SCOPE);

    for cpt in 0 to C_NB_LINE-1 loop
      uart_get_line(v_line, v_len, uart_tx, cfg);
      v_ok := false;
      for cpu in 0 to cfg.nb_cpu-1 loop
        v_ok := v_ok or (v_line(1 to v_len) = "CPU " & hex(cpu, 2) & " - Loop " & hex(cpt, 8));
      end loop;
      check_value(v_ok, ERROR, "UART line " & integer'image(cpt) & " : CPU < " & integer'image(cfg.nb_cpu) & ", counter " & integer'image(cpt) & " : " & v_line(1 to v_len), C_TB_SCOPE);
    end loop;

    wait_value (led1, C_ALL_CPU, cfg, "LED1 : every CPU has taken the lock");
    check_value(unsigned(led0) >= C_NB_LINE, ERROR, "LED0 : loop counter >= " & integer'image(C_NB_LINE) & " (0x" & to_hstring(led0) & ")", C_TB_SCOPE);

    -- No fault : the redundant CPUs of every cluster stay equal (mhartid read by each CPU)
    check_stable(led_diff, now - v_start, ERROR, "led_diff : no difference flag, no error counted by the supervisor", C_TB_SCOPE);
    check_value (led_diff, "000"        , ERROR, "led_diff = 0", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_hello_pkg;
