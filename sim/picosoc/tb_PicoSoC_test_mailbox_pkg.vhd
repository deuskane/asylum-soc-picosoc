-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_test_mailbox_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_test_mailbox_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario test_mailbox of tb_PicoSoC, from reset (firmware
--              esw/test/test_mailbox.c, 2 CPU clusters) : the requester counts
--              the answers of the responder on LED1 and shows the last one
--              on LED0
--              * LED1 = 1, 2, 3, 4 in turn (one answer per request)
--              * result line "PASS", LED0 = 0x44 ^ 0xFF
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-21  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_test_mailbox_pkg is

  -- Answers of the responder seen on the LEDs of the requester
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    );

end package tb_PicoSoC_test_mailbox_pkg;

package body tb_PicoSoC_test_mailbox_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   uart_tx  : in    std_logic
    ) is
    constant C_NB      : positive := 4; -- requests (NB_REQUEST of esw/test/test_mailbox.c)
  begin
    log(ID_SEQUENCER, "test_mailbox : requests and answers between " & integer'image(cfg.nb_cpu) & " CPUs", C_TB_SCOPE);
    check_value(cfg.nb_cpu = 2, TB_ERROR, "test_mailbox needs 2 CPU clusters", C_TB_SCOPE);

    for i in 1 to C_NB loop
      wait_value(led1, std_logic_vector(to_unsigned(i, 8)), cfg, "LED1 = " & integer'image(i) & " answers");
    end loop;

    wait_pass  ("test_mailbox", uart_tx, cfg);
    check_value(led0, x"BB", ERROR, "LED0 = last answer 0x44 ^ 0xFF", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_test_mailbox_pkg;
