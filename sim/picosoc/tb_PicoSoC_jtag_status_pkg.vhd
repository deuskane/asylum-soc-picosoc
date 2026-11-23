-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_jtag_status_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_jtag_status_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario jtag_status of tb_PicoSoC, from reset (firmware
--              user*, DEBUG_ENABLE) : the TDR PICOSOC_JTAG_IR_STATUS of the
--              injection TAP (JTAG on the UART pads, switches 10) reads,
--              from the LSB, led0_o, led1_o, led_diff_o, switch_i and the
--              resets (user SoC, supervisor SoC : 1 = running)
--              * after reset (LED1 = 0, led_diff = 0)
--              * new switches (LED0) and an it_user_i pulse (LED1 = 1)
--              * with fault injection : an error (inject_error_i) in CPU0,
--                led_diff_o = difference flags (no supervisor) or number of
--                errors (supervisor)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-22  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere Switches 0x85 (no UART line during the error)
-- 2026-11-23  1.2      mrosiere Target TAP with the chain fields of the BFM
--                               (jtag_config(cfg, tap))
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

package tb_PicoSoC_jtag_status_pkg is

  -- LEDs, switches and resets read through JTAG
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   it_user  : out   std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    );

end package tb_PicoSoC_jtag_status_pkg;

package body tb_PicoSoC_jtag_status_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   it_user  : out   std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    constant C_TAP     : natural := cfg.jtag.inject;
    -- Switches with the MSBs 10 : JTAG
    constant C_SW1     : std_logic_vector(8-1 downto 0) := x"9A";
    -- switch(5) clear : no UART line, the CPU fetches (an UART write with
    -- FIFO depth 0 stalls the bus and the fetches for a character time)
    constant C_SW2     : std_logic_vector(8-1 downto 0) := x"85";
    variable v_diff    : std_logic_vector(3-1 downto 0);

    -- Status read through JTAG : resets 11 (running), switches sw,
    -- led_diff diff, LED1 l1, LED0 l0
    procedure check_status
      (constant sw     : in std_logic_vector(8-1 downto 0)
      ;constant diff   : in std_logic_vector(3-1 downto 0)
      ;constant l1     : in std_logic_vector(8-1 downto 0)
      ;constant l0     : in std_logic_vector(8-1 downto 0)
      ;constant msg    : in string
      ) is
      constant C_EXP   : std_logic_vector(2+8+3+8+8-1 downto 0) := "11" & sw & diff & l1 & l0;
      variable v_read  : std_logic_vector(C_EXP'range);
    begin
      jtag_scan_dr (data_value => C_EXP xor C_EXP, data_out => v_read, msg => "STATUS", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
      check_value(v_read, C_EXP, ERROR, "status read through JTAG (resets, switches, led_diff, LED1, LED0) : " & msg, C_TB_SCOPE);
    end procedure;

  begin
    log(ID_SEQUENCER, "jtag_status : LEDs, switches and resets read through JTAG", C_TB_SCOPE);

    set_slv     (C_SW1, clk, switch);
    wait_value  (led0, C_SW1, cfg, "LED0 = switches 0x" & to_hstring(C_SW1) & " : UART pads to JTAG");
    chain_reset (cfg, jtag_if);
    jtag_write_ir(ir_value => PICOSOC_JTAG_IR_STATUS, msg => "STATUS", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
    check_status(C_SW1, "000", x"00", C_SW1, "after reset");

    set_slv     (C_SW2, clk, switch);
    wait_value  (led0, C_SW2, cfg, "LED0 = switches 0x" & to_hstring(C_SW2));
    pulse       (4*cfg.clk_ratio, cfg.it_on, clk, it_user);
    wait_value  (led1, x"01", cfg, "LED1 = 1 : one interruption");
    check_status(C_SW2, "000", x"01", C_SW2, "new switches, one interruption");

    if cfg.fault
    then
      -- Supervisor : one error counted ; else : difference flags of CPU0
      if cfg.supervisor
      then
        v_diff := "001";
      else
        v_diff := "101" when cfg.tmr else "001";
      end if;
      inject_error(0, cfg, clk, inject);
      wait_value  (led_diff, v_diff, cfg, "led_diff after an error in CPU0");
      if cfg.supervisor
      then
        wait_value(led0, C_SW2, cfg, "the firmware runs again after the reset (LED0 = switches)");
        wait_value(led1, x"00", cfg, "LED1 = 0 after the reset");
        check_status(C_SW2, v_diff, x"00", C_SW2, "one error counted by the supervisor");
      else
        -- After the error, the firmware of CPU0 may no longer run : the
        -- LEDs read through JTAG are compared to the pins
        check_status(C_SW2, v_diff, led1, led0, "difference flags of CPU0");
      end if;
    end if;
  end procedure;

end package body tb_PicoSoC_jtag_status_pkg;
