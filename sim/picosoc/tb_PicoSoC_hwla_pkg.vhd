-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_hwla_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_hwla_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenarios hwla and hwla_tap of tb_PicoSoC, from reset
--              (firmware user*, no supervisor, fault injection,
--              DEBUG_ENABLE ; SAFETY none, lock-step or TMR) : the HWLA of
--              PicoSoC_top captures the bus of the user CPU and the
--              difference flags around an error injection (its trigger :
--              the rising edge of the traps of PicoSoC_inject) and sends the
--              capture on its link (cfg.hwla_jtag, HWLA_LINK) :
--              - "uart" : on debug_uart_tx_o (UART 115200 8N1), received
--                with the UART BFM ;
--              - "jtag" : to the TX FIFO of jtag_axis, read through its TAP
--                (JTAG BFM : TX scans of 9 bits, a word when its bit 0
--                (valid) is set) ; then CONFIG of the TAP : TX only, 8-bit
--                words ; debug_uart_tx_o idle all along.
--              The UART pads are in mode 10 (JTAG) from the start with both
--              links, and every JTAG access has a TCK of 10 SoC clock cycles
--              at least (the limit of the TCK resynchronized in
--              PicoSoC_top) : the same stimulus times for both links.
--              * No capture before the error
--              * New switches : the firmware writes them to LED0, then an
--                error in CPU1 (CPU0 with SAFETY none) :
--                - hwla : a request of one SoC clock cycle on inject_error_i
--                  (the push button), just after the change of LED0 ; the
--                  same bytes on both links ;
--                - hwla_tap : INJECT of the injection / status TAP, the IR
--                  selected before, the DR scan just after the change of
--                  LED0 (with HWLA_LINK "jtag" the chain has one more TAP :
--                  the trigger comes one TCK later)
--              * The capture (DEPTH samples of C_SAMPLE_BYTES bytes) is
--                received, then checked :
--                - the write of LED0 with the new value is in the samples
--                  before the trigger sample
--                - the trigger sample is the sample PRE_TRIGGER, at the time
--                  of the injection : its timestamp is the one of the write
--                  of LED0 plus the clock cycles between the change of LED0
--                  and the request (hwla : exactly, plus C_INJECT_DELAY ;
--                  hwla_tap : within the DR scan of INJECT)
--                - the difference flags (field diff) : 000 up to the trigger
--                  sample ; after it, 000 all along with SAFETY none, else
--                  the flags of CPU1 (lock-step 001, TMR 011) appear and
--                  stay (sticky, no supervisor)
--                - the timestamps increase and the probes change from a
--                  sample to the next (but the trigger sample)
--                - the instruction bus matches the user ROM (copy in the
--                  testbench) : the instruction of a sample is the ROM word
--                  at the address of the previous sample when its fetch
--                  strobe (ics) is set, else the instruction of the previous
--                  sample (ROM not enabled)
--                - one capture per injection : no other byte afterwards
--              Sample (HWLA, from the LSB) : probes, then the timestamp
--              (HWLA_TIMESTAMP_WIDTH bits ; 0 : no timestamp, the checks of
--              the timestamps are skipped).
--              Probes (PicoSoC_top) : cs, re, we, ready, address, write data,
--              read data of the data bus, fetch strobe (ics), address and
--              instruction of the instruction bus, then diff.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-21  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere Probe ics : the instruction of a sample
--                               follows the fetch strobe of the previous one
-- 2026-11-23  1.2      mrosiere Loop line at every iteration (esw/demo/user.c) :
--                               read of the switches of the next iteration
-- 2026-11-24  1.3      mrosiere DEPTH, PRE_TRIGGER and timestamp width from
--                               the generics of the DUT (cfg)
-- 2026-11-24  1.4      mrosiere HWLA_TIMESTAMP_WIDTH = 0 (no timestamp)
-- 2026-11-27  1.5      mrosiere HWLA_LINK "jtag" : capture read through the
--                               TAP of jtag_axis (JTAG BFM), its CONFIG
-- 2026-11-27  2.0      mrosiere Trigger on the error injection (button :
--                               hwla, TAP INJECT : hwla_tap) in every
--                               safety configuration ; field diff ; one
--                               capture per injection (was : trigger on
--                               diff, next capture checked)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_uart;
use     bitvis_vip_uart.uart_bfm_pkg.all;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;

library asylum;
use     asylum.PicoSoC_pkg.all;
use     asylum.GPIO_irq_csr_pkg.all;
use     asylum.jtag_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;

package tb_PicoSoC_hwla_pkg is

  -- Capture of an error injected by the push button (tap false) or by the
  -- TAP INJECT (tap true), received on debug_uart_tx_o or through the TAP
  -- of jtag_axis (cfg.hwla_jtag)
  procedure run
    (constant cfg           : in    t_tb_cfg
    ;constant tap           : in    boolean
    ;signal   clk           : in    std_logic
    ;signal   switch        : out   std_logic_vector
    ;signal   mux_sel       : out   std_logic_vector
    ;signal   inject        : out   std_logic_vector
    ;signal   led0          : in    std_logic_vector
    ;signal   led_diff      : in    std_logic_vector
    ;signal   debug_uart_tx : in    std_logic
    ;signal   jtag_if       : inout t_jtag_if
    ;signal   rom_addr      : out   std_logic_vector
    ;signal   rom_data      : in    std_logic_vector
    );

end package tb_PicoSoC_hwla_pkg;

package body tb_PicoSoC_hwla_pkg is

  procedure run
    (constant cfg           : in    t_tb_cfg
    ;constant tap           : in    boolean
    ;signal   clk           : in    std_logic
    ;signal   switch        : out   std_logic_vector
    ;signal   mux_sel       : out   std_logic_vector
    ;signal   inject        : out   std_logic_vector
    ;signal   led0          : in    std_logic_vector
    ;signal   led_diff      : in    std_logic_vector
    ;signal   debug_uart_tx : in    std_logic
    ;signal   jtag_if       : inout t_jtag_if
    ;signal   rom_addr      : out   std_logic_vector
    ;signal   rom_data      : in    std_logic_vector
    ) is
    -- Configuration of the HWLA in PicoSoC_top (generics HWLA_*)
    constant C_DEPTH        : positive := cfg.hwla_depth;
    constant C_PRE_TRIGGER  : natural  := cfg.hwla_pre_trigger;
    constant C_TS_WIDTH     : natural  := cfg.hwla_ts_width;  -- 0 : no timestamp
    constant C_BIT_TIME     : time     := 1 sec / 115200;

    -- Sample : probes (fields below, from the LSB), then the timestamp
    constant C_AW           : positive := rom_addr'length;  -- instruction address
    constant C_DW           : positive := rom_data'length;  -- instruction
    constant C_NB_PROBE     : positive := 4 + 3*8 + 1 + C_AW + C_DW + 3;
    constant C_SAMPLE_BYTES : positive := (C_NB_PROBE + C_TS_WIDTH + 7) / 8;
    constant C_DCS          : natural  := 0;
    constant C_DRE          : natural  := 1;
    constant C_DWE          : natural  := 2;
    constant C_DREADY       : natural  := 3;
    constant C_DADDR        : natural  := 4;
    constant C_DWDATA       : natural  := 12;
    constant C_DRDATA       : natural  := 20;
    constant C_ICS          : natural  := 28;
    constant C_IADDR        : natural  := 29;
    constant C_IDATA        : natural  := C_IADDR + C_AW;
    constant C_DIFF         : natural  := C_IDATA + C_DW;
    constant C_TS           : natural  := C_NB_PROBE;

    -- SoC clock cycles from the request on inject_error_i (set on a falling
    -- edge of clk_i) to the trigger sample : resynchronization (2), trap
    -- (1), input stage of the HWLA (1), the accepted write of LED0 (ready)
    -- being on the edge that updates led0_o
    constant C_INJECT_DELAY : natural  := 4;
    -- No byte of another capture during C_SETTLE cycles after the capture
    constant C_SETTLE       : positive := 2000*cfg.clk_ratio;

    -- Data register of the switches and of LED0
    constant C_SWITCH_DATA  : std_logic_vector(8-1 downto 0) := std_logic_vector(unsigned(PICOSOC_USER_SWITCH_BA) + GPIO_IRQ_DATA);
    constant C_LED0_DATA    : std_logic_vector(8-1 downto 0) := std_logic_vector(unsigned(PICOSOC_USER_LED0_BA  ) + GPIO_IRQ_DATA);

    -- The firmware loops on SWITCH -> loop line -> LED0
    constant C_SW1          : std_logic_vector(8-1 downto 0) := x"5A";
    constant C_SW2          : std_logic_vector(8-1 downto 0) := x"96";

    subtype  t_sample      is std_logic_vector(8*C_SAMPLE_BYTES-1 downto 0);
    type     t_capture     is array (0 to C_DEPTH-1) of t_sample;

    variable v_uart         : t_uart_bfm_config := cfg.uart;
    variable v_capture      : t_capture;
    variable v_byte         : std_logic_vector(8-1 downto 0);
    variable v_t0           : time;
    variable v_t_led        : time;
    variable v_t_inj        : time;      -- the request (button) or the start of the DR scan of INJECT (TAP)
    variable v_t_inj_end    : time;      -- the end of the DR scan of INJECT (TAP)
    variable v_inject       : std_logic_vector(16-1 downto 0); -- INJECT : [2:0] outside the CPUs
    variable v_read16       : std_logic_vector(16-1 downto 0); -- INJECT : diff in [2:0]
    variable v_jtag_inject  : t_jtag_bfm_config;
    variable v_diff         : std_logic_vector(3-1 downto 0);
    variable v_first_diff   : integer;
    variable v_err_diff     : natural := 0;
    variable v_cycles_max   : natural;
    variable v_t_start      : time;
    -- Copy with the error (SAFETY none : CPU0, else CPU1), its difference
    -- flags (no supervisor : sticky)
    variable v_cpu          : natural;
    variable v_diff_error   : std_logic_vector(3-1 downto 0);
    variable v_write        : integer;
    variable v_cycles       : natural;
    variable v_delta        : natural;
    variable v_err_sample   : natural := 0;
    variable v_err_rom      : natural := 0;
    variable v_rom          : std_logic_vector(C_DW-1 downto 0);
    variable v_idata        : std_logic_vector(C_DW-1 downto 0);

    -- HWLA_LINK "jtag" : TAP of jtag_axis, the other TAPs in BYPASS ; TCK of
    -- at least 10 SoC clock cycles (resynchronized in PicoSoC_top)
    variable v_jtag         : t_jtag_bfm_config;
    variable v_word         : std_logic_vector(8 downto 0);  -- {word, valid}
    variable v_config       : std_logic_vector(JTAG_AXIS_CONFIG_WIDTH-1 downto 0);
    variable v_t_byte       : time;

    -- Field of a sample
    function field (s : t_sample; lsb : natural; width : positive) return std_logic_vector is
    begin
      return s(lsb+width-1 downto lsb);
    end function;

    -- Timestamp difference of two samples (modulo 2**C_TS_WIDTH)
    function ts_delta (s1, s0 : t_sample) return natural is
    begin
      return to_integer(unsigned(field(s1, C_TS, C_TS_WIDTH)) - unsigned(field(s0, C_TS, C_TS_WIDTH)));
    end function;

    -- Timestamp 0 : a sample stored even when the probes did not change
    -- (never without timestamp)
    function ts_zero (s : t_sample) return boolean is
    begin
      if C_TS_WIDTH = 0
      then
        return false;
      end if;
      return unsigned(field(s, C_TS, C_TS_WIDTH)) = 0;
    end function;

  begin
    if not cfg.fault
    then
      v_cpu := 0; v_diff_error := "000";  -- SAFETY none : no copy to compare with
    elsif cfg.tmr
    then
      v_cpu := 1; v_diff_error := "011";  -- CPU0 vs CPU1, CPU1 vs CPU2
    else
      v_cpu := 1; v_diff_error := "001";  -- CPU0 vs CPU1
    end if;
    v_inject        := (others => '0');
    v_inject(v_cpu) := '1';

    -- UART pads to JTAG at once with both links (the same stimulus times),
    -- TCK of 10 SoC clock cycles at least
    mux_sel <= C_MUX_JTAG;
    v_jtag_inject            := jtag_config(cfg, cfg.jtag.inject);
    v_jtag_inject.tck_period := maximum(v_jtag_inject.tck_period, 10 * cfg.clk_ratio * cfg.clk_period);
    if cfg.hwla_jtag
    then
      v_jtag            := jtag_config(cfg, cfg.jtag.hwla);
      v_jtag.tck_period := maximum(v_jtag.tck_period, 10 * cfg.clk_ratio * cfg.clk_period);
    end if;
    if tap
    then
      log(ID_SEQUENCER, "hwla_tap : capture of an error injected in CPU" & integer'image(v_cpu) & " by the TAP INJECT", C_TB_SCOPE);
    else
      log(ID_SEQUENCER, "hwla : capture of an error injected in CPU" & integer'image(v_cpu) & " by the push button", C_TB_SCOPE);
    end if;
    v_t0      := now;
    v_t_start := now;

    set_slv     (C_SW1, clk, switch);
    wait_value  (led0, C_SW1, cfg, "LED0 = switches");
    if tap
    then
      -- INJECT selected before the stimulus
      jtag_reset   (msg => "Test-Logic-Reset", jtag_if => jtag_if, scope => C_TB_SCOPE, config => v_jtag_inject);
      jtag_write_ir(ir_value => PICOSOC_JTAG_IR_INJECT, msg => "INJECT", jtag_if => jtag_if, scope => C_TB_SCOPE, config => v_jtag_inject);
    end if;
    check_value (debug_uart_tx, '1', ERROR, "debug_uart_tx_o idle", C_TB_SCOPE);
    check_stable(debug_uart_tx, now - v_t0, ERROR, "debug_uart_tx_o : no capture without error", C_TB_SCOPE);

    -- New switches, then an error just after their write to LED0 : both in
    -- the capture
    set_slv     (C_SW2, clk, switch);
    wait_value  (led0, C_SW2, cfg, "LED0 = new switches");
    v_t_led  := now;
    if tap
    then
      -- The trap is set at the Update-DR of the scan (then synchronized) ;
      -- INJECT keeps the request until a Test-Logic-Reset
      v_t_inj     := now;
      jtag_scan_dr(data_value => v_inject, data_out => v_read16, msg => "INJECT : an error in CPU" & integer'image(v_cpu), jtag_if => jtag_if, scope => C_TB_SCOPE, config => v_jtag_inject);
      v_t_inj_end := now;
      check_value (v_read16, x"0000", ERROR, "diff read through JTAG before the injection", C_TB_SCOPE);
      v_cycles     := (v_t_inj     - v_t_led) / (cfg.clk_ratio * cfg.clk_period);
      v_cycles_max := (v_t_inj_end - v_t_led) / (cfg.clk_ratio * cfg.clk_period) + C_INJECT_DELAY + 2;
      log(ID_SEQUENCER_SUB, "INJECT : DR scan from " & integer'image(v_cycles) & " to " & integer'image(v_cycles_max - C_INJECT_DELAY - 2) & " cycles after the change of LED0", C_TB_SCOPE);
    else
      -- A request of one SoC clock cycle (the trap keeps it)
      wait until falling_edge(clk);
      v_t_inj := now;
      inject(v_cpu) <= cfg.fault_on;
      for c in 1 to cfg.clk_ratio loop
        wait until falling_edge(clk);
      end loop;
      inject(v_cpu) <= not cfg.fault_on;
      v_cycles := (v_t_inj - v_t_led) / (cfg.clk_ratio * cfg.clk_period);
      log(ID_SEQUENCER_SUB, "Request " & integer'image(v_cycles) & " cycles after the change of LED0", C_TB_SCOPE);
    end if;

    -- Capture : DEPTH samples, a sample in C_SAMPLE_BYTES bytes from the LSB
    v_uart.bit_time := C_BIT_TIME;
    if cfg.hwla_jtag
    then
      -- Test-Logic-Reset, instruction TX of jtag_axis ; one TX scan per word,
      -- not logged (one scan per byte)
      jtag_reset   (msg => "Test-Logic-Reset", jtag_if => jtag_if, scope => C_TB_SCOPE, config => v_jtag);
      jtag_write_ir(ir_value => JTAG_AXIS_IR_TX, msg => "TX of jtag_axis", jtag_if => jtag_if, scope => C_TB_SCOPE, config => v_jtag);
      v_jtag.id_for_bfm := ID_NEVER;
    end if;
    for i in 0 to C_DEPTH*C_SAMPLE_BYTES-1 loop
      if cfg.hwla_jtag
      then
        -- TX scans until a valid word (the FIFO is empty until the capture)
        v_t_byte := now;
        loop
          jtag_scan_dr(data_value => "000000000",
                       data_out   => v_word,
                       msg        => "HWLA byte " & integer'image(i),
                       jtag_if    => jtag_if,
                       scope      => C_TB_SCOPE,
                       config     => v_jtag);
          exit when v_word(0) = '1';
          if now - v_t_byte > cfg.timeout
          then
            alert(ERROR, "HWLA byte " & integer'image(i) & " : TX FIFO of jtag_axis empty for " & time'image(cfg.timeout), C_TB_SCOPE);
            exit;
          end if;
        end loop;
        v_byte := v_word(8 downto 1);
      else
        uart_receive(data_value     => v_byte,
                     msg            => "HWLA byte " & integer'image(i),
                     rx             => debug_uart_tx,
                     terminate_loop => uart_no_terminate,
                     config         => v_uart,
                     scope          => C_TB_SCOPE);
      end if;
      v_capture(i / C_SAMPLE_BYTES)(8*(i mod C_SAMPLE_BYTES)+7 downto 8*(i mod C_SAMPLE_BYTES)) := v_byte;
    end loop;
    for s in 0 to C_DEPTH-1 loop
      log(ID_SEQUENCER_SUB, "HWLA sample " & integer'image(s) & " : " & to_hstring(v_capture(s)), C_TB_SCOPE);
    end loop;

    -- One capture per injection : nothing more on the link
    v_t0 := now;
    wait_cycles (C_SETTLE, clk);
    if cfg.hwla_jtag
    then
      jtag_scan_dr(data_value => "000000000", data_out => v_word, msg => "TX of jtag_axis", jtag_if => jtag_if, scope => C_TB_SCOPE, config => v_jtag);
      check_value (v_word(0), '0', ERROR, "one capture per injection : TX FIFO of jtag_axis empty", C_TB_SCOPE);
    else
      check_stable(debug_uart_tx, now - v_t0, ERROR, "one capture per injection : debug_uart_tx_o idle after the capture", C_TB_SCOPE);
    end if;

    -- Data bus : first accepted write of the new switches to LED0
    v_write := -1;
    for s in C_DEPTH-1 downto 0 loop
      if (v_capture(s)(C_DCS) = '1') and (v_capture(s)(C_DWE) = '1') and (v_capture(s)(C_DREADY) = '1') and
         (field(v_capture(s), C_DADDR , 8) = C_LED0_DATA) and
         (field(v_capture(s), C_DWDATA, 8) = C_SW2)
      then
        v_write := s;
      end if;
    end loop;
    check_value(v_write >= 0 and v_write < C_PRE_TRIGGER, ERROR, "Sample " & integer'image(v_write) & " (before the trigger) : write of the new switches to LED0", C_TB_SCOPE);

    -- Trigger sample : sample PRE_TRIGGER, at the time of the injection
    if (v_write >= 0) and (C_TS_WIDTH > 0)
    then
      v_delta := ts_delta(v_capture(C_PRE_TRIGGER), v_capture(v_write));
      if tap
      then
        check_value(v_delta >= v_cycles and v_delta <= v_cycles_max, ERROR,
                    "Trigger sample " & integer'image(C_PRE_TRIGGER) & " : " & integer'image(v_delta) & " cycles after the write of LED0, within the DR scan of INJECT", C_TB_SCOPE);
      else
        check_value(v_delta, v_cycles + C_INJECT_DELAY, ERROR,
                    "Trigger sample " & integer'image(C_PRE_TRIGGER) & " : cycles after the write of LED0 (the request of the push button)", C_TB_SCOPE);
      end if;
    end if;

    -- Difference flags : 000 up to the trigger sample, then the flags of
    -- the copy with the error appear and stay (000 with SAFETY none)
    v_first_diff := -1;
    for s in 0 to C_DEPTH-1 loop
      v_diff := field(v_capture(s), C_DIFF, 3);
      if (s <= C_PRE_TRIGGER and v_diff /= "000") or
         (s >  C_PRE_TRIGGER and v_first_diff >= 0 and v_diff /= v_diff_error) or
         (v_diff /= "000" and (v_diff and not v_diff_error) /= "000")
      then
        v_err_diff := v_err_diff + 1;
        log(ID_SEQUENCER_SUB, "Sample " & integer'image(s) & " : diff " & to_string(v_diff), C_TB_SCOPE);
      end if;
      if v_first_diff < 0 and v_diff = v_diff_error and v_diff /= "000"
      then
        v_first_diff := s;
      end if;
    end loop;
    check_value(v_err_diff, 0, ERROR, "Field diff : 000 up to the trigger sample, then only the flags " & to_string(v_diff_error) & " of CPU" & integer'image(v_cpu), C_TB_SCOPE);
    if v_diff_error /= "000"
    then
      check_value(v_first_diff > C_PRE_TRIGGER, ERROR, "Field diff : the flags " & to_string(v_diff_error) & " appear after the trigger (sample " & integer'image(v_first_diff) & ") and stay", C_TB_SCOPE);
      if v_first_diff > C_PRE_TRIGGER and C_TS_WIDTH > 0
      then
        log(ID_SEQUENCER_SUB, "Difference flags " & integer'image(ts_delta(v_capture(v_first_diff), v_capture(C_PRE_TRIGGER))) & " cycles after the trigger", C_TB_SCOPE);
      end if;
    else
      check_value(field(v_capture(C_DEPTH-1), C_DIFF, 3), "000", ERROR, "Field diff : 000 all along (SAFETY none : no copy to compare with)", C_TB_SCOPE);
    end if;

    -- Each pair of consecutive samples : timestamps, changes only (but the
    -- trigger sample and the timestamp 0), instruction bus
    for s in 1 to C_DEPTH-1 loop
      v_delta := 1;
      if C_TS_WIDTH > 0
      then
        v_delta := ts_delta(v_capture(s), v_capture(s-1));
      end if;
      if (v_delta = 0) or (v_delta > 1000) or
         ((field(v_capture(s), 0, C_NB_PROBE) = field(v_capture(s-1), 0, C_NB_PROBE)) and
          (s /= C_PRE_TRIGGER) and not ts_zero(v_capture(s)))
      then
        v_err_sample := v_err_sample + 1;
        log(ID_SEQUENCER_SUB, "Sample " & integer'image(s) & " : " & integer'image(v_delta) & " cycles after the previous one, same probes", C_TB_SCOPE);
      end if;

      rom_addr <= field(v_capture(s-1), C_IADDR, C_AW);
      wait until rising_edge(clk);
      wait until falling_edge(clk);
      -- ROM enabled by ics : the word at the address, else unchanged
      if v_capture(s-1)(C_ICS) = '1'
      then
        v_rom  := rom_data;
      else
        v_rom  := field(v_capture(s-1), C_IDATA, C_DW);
      end if;
      v_idata  := field(v_capture(s), C_IDATA, C_DW);
      if v_idata /= v_rom
      then
        v_err_rom := v_err_rom + 1;
        log(ID_SEQUENCER_SUB, "Sample " & integer'image(s) & " : instruction " & to_hstring(v_idata) & ", ROM " & to_hstring(v_rom), C_TB_SCOPE);
      end if;
    end loop;
    check_value(v_err_sample, 0, ERROR, "Samples : timestamps increase (if any), probes change (but the trigger sample)", C_TB_SCOPE);
    check_value(v_err_rom   , 0, ERROR, "Instruction bus of the capture matches the user ROM", C_TB_SCOPE);

    -- HWLA_LINK "jtag" : CONFIG of jtag_axis (TX enabled, RX disabled : its
    -- flags empty and full, 8-bit words ; TX empty), nothing on
    -- debug_uart_tx_o
    if cfg.hwla_jtag
    then
      v_jtag.id_for_bfm := ID_BFM;
      jtag_write_ir(ir_value => JTAG_AXIS_IR_CONFIG, msg => "CONFIG of jtag_axis", jtag_if => jtag_if, scope => C_TB_SCOPE, config => v_jtag);
      jtag_scan_dr (data_value => x"0000", data_out => v_config, msg => "CONFIG of jtag_axis", jtag_if => jtag_if, scope => C_TB_SCOPE, config => v_jtag);
      check_value(v_config and x"FF71", x"0861", ERROR,
                  "CONFIG of jtag_axis : TX_ENABLE 1, RX_ENABLE 0, RX empty and full, DATA_WIDTH 8", C_TB_SCOPE);
      check_stable(debug_uart_tx, now - v_t_start, ERROR, "debug_uart_tx_o : idle with HWLA_LINK jtag", C_TB_SCOPE);
    end if;
  end procedure;

end package body tb_PicoSoC_hwla_pkg;
