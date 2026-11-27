-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_jtag_status_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_jtag_status_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario jtag_status of tb_PicoSoC, from reset (firmware
--              user*, DEBUG_ENABLE) : the TDR PICOSOC_JTAG_IR_STATUS of the
--              injection TAP (JTAG on the UART pads, debug_mux_sel_i 10) reads,
--              from the LSB, led0_o, led1_o, led_diff_o, switch_i, the
--              resets (user SoC, supervisor SoC : 1 = running) and the flags
--              of the HWLA (arm, armed, triggered, sending)
--              * HWLA flags : arm tied to 1, so the HWLA is armed from the
--                reset (no state "not armed" to read) ; the expected flags
--                are polled (STATUS scans, bounded) before the check : the
--                HWLA moves on the SoC clock
--              * after reset (LED1 = 0, led_diff = 0)
--              * new switches (LED0) and an it_user_i pulse (LED1 = 1)
--              * with fault injection : an error (inject_error_i) in CPU0,
--                a request of one cycle trapped until the difference flag
--                (the CPU waits on the UART most of the time : the trap of
--                PicoSoC_inject waits for its fetch), led_diff_o = difference flags (no supervisor) or number of
--                errors (supervisor) ; the HWLA triggered, sending its
--                capture (to the UART or to the TX FIFO of jtag_axis)
--              * HWLA_LINK "jtag" with a supervisor : the capture read
--                through the TAP of jtag_axis (TX scans until the FIFO is
--                empty : the bytes of one capture), then the HWLA armed
--                again (the reset of the user SoC cleared the difference
--                flag : no new trigger). With the UART link, the end of the
--                capture (about 60 ms at 115200 baud) is not waited for
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-22  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere Switches 0x85 (no UART line during the error)
-- 2026-11-23  1.2      mrosiere Target TAP with the chain fields of the BFM
--                               (jtag_config(cfg, tap))
-- 2026-11-23  1.3      mrosiere Loop line at every iteration (esw/demo/user.c) :
--                               error held until the difference flag
-- 2026-11-23  1.4      mrosiere UART pads to JTAG with debug_mux_sel_i (was
--                               the switch MSBs) : switches 0x1A, 0x05
-- 2026-11-26  1.5      mrosiere Error : a request of one cycle (trapped),
--                               no longer held until the difference flag
-- 2026-11-27  1.6      mrosiere Flags of the HWLA above the resets ; capture
--                               read through jtag_axis (HWLA_LINK "jtag")
-- 2026-11-27  1.7      mrosiere Capture : the difference flags in the probes
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;

library asylum;
use     asylum.PicoSoC_pkg.all;
use     asylum.ROM_user_pkg.all;
use     asylum.jtag_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;

package tb_PicoSoC_jtag_status_pkg is

  -- LEDs, switches, resets and flags of the HWLA read through JTAG
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
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
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   it_user  : out   std_logic
    ;signal   inject   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   led1     : in    std_logic_vector
    ;signal   led_diff : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    constant C_TAP     : natural := cfg.jtag.inject;
    constant C_SW1     : std_logic_vector(8-1 downto 0) := x"1A";
    constant C_SW2     : std_logic_vector(8-1 downto 0) := x"05";
    variable v_diff    : std_logic_vector(3-1 downto 0);

    -- Flags of the HWLA (from the LSB : arm, armed, triggered, sending)
    constant C_ARMED   : std_logic_vector(4-1 downto 0) := "0011";  -- armed, waiting for the trigger
    constant C_SENDING : std_logic_vector(4-1 downto 0) := "1101";  -- triggered, capture being sent
    -- Bytes of a capture of the HWLA : HWLA_DEPTH samples of the probes of
    -- PicoSoC_top (the buses of the user CPU, the difference flags) and the
    -- timestamp
    constant C_NB_PROBE: positive := 4 + 3*8 + 1 + ROM_user_ADDR_WIDTH + ROM_user_DATA_WIDTH + 3;
    constant C_BYTES   : positive := cfg.hwla_depth * ((C_NB_PROBE + cfg.hwla_ts_width + 7) / 8);
    variable v_word    : std_logic_vector(8 downto 0);  -- {word, valid} of jtag_axis
    variable v_count   : natural;
    variable v_jtag    : t_jtag_bfm_config;

    -- Status read through JTAG (instruction STATUS selected) : HWLA flags
    -- hwla (read until they are the expected ones, at most 100 scans),
    -- resets 11 (running), switches sw, led_diff diff, LED1 l1, LED0 l0
    procedure check_status
      (constant hwla   : in std_logic_vector(4-1 downto 0)
      ;constant sw     : in std_logic_vector(8-1 downto 0)
      ;constant diff   : in std_logic_vector(3-1 downto 0)
      ;constant l1     : in std_logic_vector(8-1 downto 0)
      ;constant l0     : in std_logic_vector(8-1 downto 0)
      ;constant msg    : in string
      ) is
      constant C_EXP   : std_logic_vector(4+2+8+3+8+8-1 downto 0) := hwla & "11" & sw & diff & l1 & l0;
      variable v_read  : std_logic_vector(C_EXP'range);
    begin
      for i in 1 to 100 loop
        jtag_scan_dr (data_value => C_EXP xor C_EXP, data_out => v_read, msg => "STATUS", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
        exit when v_read(C_EXP'high downto C_EXP'high-3) = hwla;
      end loop;
      check_value(v_read, C_EXP, ERROR, "status read through JTAG (HWLA flags, resets, switches, led_diff, LED1, LED0) : " & msg, C_TB_SCOPE);
    end procedure;

  begin
    log(ID_SEQUENCER, "jtag_status : LEDs, switches and resets read through JTAG", C_TB_SCOPE);

    set_slv     (C_MUX_JTAG, clk, mux_sel);
    set_slv     (C_SW1, clk, switch);
    wait_value  (led0, C_SW1, cfg, "LED0 = switches 0x" & to_hstring(C_SW1) & " : UART pads to JTAG");
    chain_reset (cfg, jtag_if);
    jtag_write_ir(ir_value => PICOSOC_JTAG_IR_STATUS, msg => "STATUS", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
    check_status(C_ARMED, C_SW1, "000", x"00", C_SW1, "after reset, HWLA armed");

    set_slv     (C_SW2, clk, switch);
    wait_value  (led0, C_SW2, cfg, "LED0 = switches 0x" & to_hstring(C_SW2));
    pulse       (4*cfg.clk_ratio, cfg.it_on, clk, it_user);
    wait_value  (led1, x"01", cfg, "LED1 = 1 : one interruption");
    check_status(C_ARMED, C_SW2, "000", x"01", C_SW2, "new switches, one interruption, HWLA armed");

    if cfg.fault
    then
      -- Supervisor : one error counted ; else : difference flags of CPU0
      if cfg.supervisor
      then
        v_diff := "001";
      else
        v_diff := "101" when cfg.tmr else "001";
      end if;
      -- A request of one cycle : the trap keeps the error until the
      -- difference flag (an UART write with FIFO depth 0 stalls the bus and
      -- the fetches for a character time). A request held until led_diff
      -- changes would outlive the reset of the user SoC and set the trap
      -- again (a second error)
      inject_error(0, cfg, clk, inject);
      wait_value  (led_diff, v_diff, cfg, "led_diff after an error in CPU0");
      if cfg.supervisor
      then
        wait_value(led0, C_SW2, cfg, "the firmware runs again after the reset (LED0 = switches)");
        wait_value(led1, x"00", cfg, "LED1 = 0 after the reset");
        check_status(C_SENDING, C_SW2, v_diff, x"00", C_SW2, "one error counted by the supervisor, HWLA triggered and sending");

        -- HWLA_LINK "jtag" : the capture read through the TAP of jtag_axis,
        -- then the HWLA armed again (no difference flag after the reset)
        if cfg.hwla_jtag
        then
          v_jtag            := jtag_config(cfg, cfg.jtag.hwla);
          jtag_write_ir(ir_value => JTAG_AXIS_IR_TX, msg => "TX of jtag_axis", jtag_if => jtag_if, scope => C_TB_SCOPE, config => v_jtag);
          v_jtag.id_for_bfm := ID_NEVER;
          v_count           := 0;
          loop
            jtag_scan_dr(data_value => "000000000", data_out => v_word, msg => "HWLA byte", jtag_if => jtag_if, scope => C_TB_SCOPE, config => v_jtag);
            exit when v_word(0) = '0' or v_count > C_BYTES;
            v_count := v_count + 1;
          end loop;
          check_value(v_count, C_BYTES, ERROR, "bytes of the capture read through jtag_axis until its TX FIFO is empty", C_TB_SCOPE);
          jtag_write_ir(ir_value => PICOSOC_JTAG_IR_STATUS, msg => "STATUS", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, C_TAP));
          check_status(C_ARMED, C_SW2, v_diff, x"00", C_SW2, "capture read, HWLA armed again");
        end if;
      else
        -- After the error, the firmware of CPU0 may no longer run : the
        -- LEDs read through JTAG are compared to the pins
        check_status(C_SENDING, C_SW2, v_diff, led1, led0, "difference flags of CPU0, HWLA triggered and sending");
      end if;
    end if;
  end procedure;

end package body tb_PicoSoC_jtag_status_pkg;
