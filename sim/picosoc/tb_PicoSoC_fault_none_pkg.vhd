-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_fault_none_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_fault_none_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario fault_none of tb_PicoSoC, from reset (firmware
--              user_loop, supervisor, SAFETY none, fault injection) : an
--              error injected in the only CPU derails the firmware and
--              nothing detects it
--              * the first lines are the xorwow sequence
--              * a request of one SoC clock cycle on inject_error_i(0) (a
--                short push of the button), just after a line : the trap of
--                PicoSoC_inject keeps the error (no difference flag clears
--                it), the bit SEU_BIT(0) of every instruction is flipped
--              * the firmware derails : its next lines differ from the
--                sequence, or it stops printing
--              * no copy to compare with : no difference flag, the
--                supervisor does not reset the user SoC and its error
--                counter (led_diff_o) stays 0
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-25  1.0      mrosiere Created
-- 2026-11-27  1.1      mrosiere Firmware user_loop : request of one SoC cycle
--                               (trapped), the printed sequence diverges or
--                               stops
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_sequence_pkg.all;

package tb_PicoSoC_fault_none_pkg is

  -- An error in CPU0 : the firmware derails, led_diff stays 0
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_fault_none_pkg;

package body tb_PicoSoC_fault_none_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    ) is
    variable v_line    : string(1 to 64);
    variable v_len     : natural;
    variable v_ok      : boolean := true;
    variable v_derail  : boolean := false;
    variable v_t0      : time;
  begin
    log(ID_SEQUENCER, "fault_none : an error in the only CPU, the firmware derails, the supervisor sees nothing", C_TB_SCOPE);

    v_t0 := now;
    check_lines (0, 2, "before the error", uart_tx, cfg);
    check_value (led_diff, "000", ERROR, "led_diff : no error yet", C_TB_SCOPE);

    -- A request of one SoC clock cycle : trapped until the power-on reset
    inject_error(0, cfg, clk, inject);
    for i in 2 to 2+C_NB_LINES-1 loop
      get_line(v_line, v_len, v_ok, uart_tx, cfg);
      if not v_ok
      then
        log(ID_SEQUENCER_SUB, "Line " & integer'image(i) & " : the firmware stopped printing", C_TB_SCOPE);
        v_derail := true;
      elsif v_line(1 to v_len) /= loop_line(i)
      then
        log(ID_SEQUENCER_SUB, "Line " & integer'image(i) & " : " & v_line(1 to v_len) & " instead of " & loop_line(i), C_TB_SCOPE);
        v_derail := true;
      end if;
      exit when v_derail;
    end loop;
    check_value (v_derail, ERROR, "the firmware derails : its lines leave the xorwow sequence or stop", C_TB_SCOPE);
    check_stable(led_diff, now - v_t0, ERROR, "led_diff stable after the error : the supervisor did not react", C_TB_SCOPE);
    check_value (led_diff, "000", ERROR, "led_diff = 0 : no difference flag, no reset of the user SoC by the supervisor", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_fault_none_pkg;
