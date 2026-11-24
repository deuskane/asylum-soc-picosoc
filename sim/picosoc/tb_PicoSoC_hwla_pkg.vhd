-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_hwla_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_hwla_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario hwla of tb_PicoSoC, from reset (firmware user*, no
--              supervisor, lock-step or TMR, fault injection, DEBUG_ENABLE) :
--              the HWLA of PicoSoC_top captures the bus of the user CPU
--              around a difference of the redundant CPUs and sends the
--              capture on debug_uart_tx_o (UART 115200 8N1).
--              * No byte on debug_uart_tx_o before the error
--              * New switches : the firmware writes them to LED0 (time of
--                the change of LED0), then an error in CPU1 (time of the
--                difference flag on led_diff_o)
--              * The capture (DEPTH samples of C_SAMPLE_BYTES bytes) is
--                received with the UART BFM, then checked :
--                - the write of LED0 with the new value is in the samples
--                  before the trigger sample, the read of the switches of
--                  the next loop iteration (still the new value) follows it
--                  (the read of the iteration that wrote LED0 is a whole
--                  loop line earlier, out of the capture)
--                - the trigger sample is the sample PRE_TRIGGER : its
--                  timestamp is the one of the write of LED0, plus the clock
--                  cycles between the change of LED0 and the difference flag
--                - capture size : the next capture (the flag stays set)
--                  does not continue this one
--                - the timestamps increase and the probes change from a
--                  sample to the next (but the trigger sample)
--                - the instruction bus matches the user ROM (copy in the
--                  testbench) : the instruction of a sample is the ROM word
--                  at the address of the previous sample when its fetch
--                  strobe (ics) is set, else the instruction of the previous
--                  sample (ROM not enabled)
--              Sample (HWLA, from the LSB) : probes, then the timestamp
--              (HWLA_TIMESTAMP_WIDTH bits ; 0 : no timestamp, the checks of
--              the timestamps are skipped).
--              Probes (PicoSoC_top) : cs, re, we, ready, address, write data,
--              read data of the data bus, then fetch strobe (ics), address
--              and instruction of the instruction bus.
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
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_uart;
use     bitvis_vip_uart.uart_bfm_pkg.all;

library asylum;
use     asylum.PicoSoC_pkg.all;
use     asylum.GPIO_irq_csr_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_hwla_pkg is

  -- Capture of an error in CPU1, received on debug_uart_tx_o
  procedure run
    (constant cfg           : in    t_tb_cfg
    ;signal   clk           : in    std_logic
    ;signal   switch        : out   std_logic_vector
    ;signal   inject        : out   std_logic_vector
    ;signal   led0          : in    std_logic_vector
    ;signal   led_diff      : in    std_logic_vector
    ;signal   debug_uart_tx : in    std_logic
    ;signal   rom_addr      : out   std_logic_vector
    ;signal   rom_data      : in    std_logic_vector
    );

end package tb_PicoSoC_hwla_pkg;

package body tb_PicoSoC_hwla_pkg is

  procedure run
    (constant cfg           : in    t_tb_cfg
    ;signal   clk           : in    std_logic
    ;signal   switch        : out   std_logic_vector
    ;signal   inject        : out   std_logic_vector
    ;signal   led0          : in    std_logic_vector
    ;signal   led_diff      : in    std_logic_vector
    ;signal   debug_uart_tx : in    std_logic
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
    constant C_NB_PROBE     : positive := 4 + 3*8 + 1 + C_AW + C_DW;
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
    constant C_TS           : natural  := C_NB_PROBE;

    -- The trigger sample is sampled by the HWLA one clock cycle after the
    -- edge that sets the difference flag, the accepted write of LED0
    -- (ready) on the edge that updates led0_o
    constant C_TRIGGER_DELAY: natural  := 1;

    -- Data register of the switches and of LED0
    constant C_SWITCH_DATA  : std_logic_vector(8-1 downto 0) := std_logic_vector(unsigned(PICOSOC_USER_SWITCH_BA) + GPIO_IRQ_DATA);
    constant C_LED0_DATA    : std_logic_vector(8-1 downto 0) := std_logic_vector(unsigned(PICOSOC_USER_LED0_BA  ) + GPIO_IRQ_DATA);

    -- The firmware loops on SWITCH -> loop line -> LED0
    constant C_SW1          : std_logic_vector(8-1 downto 0) := x"5A";
    constant C_SW2          : std_logic_vector(8-1 downto 0) := x"96";

    subtype  t_sample      is std_logic_vector(8*C_SAMPLE_BYTES-1 downto 0);
    type     t_capture     is array (0 to C_DEPTH) of t_sample;  -- and the first sample of the next capture

    variable v_uart         : t_uart_bfm_config := cfg.uart;
    variable v_capture      : t_capture;
    variable v_byte         : std_logic_vector(8-1 downto 0);
    variable v_t0           : time;
    variable v_t_led        : time;
    variable v_t_diff       : time;
    variable v_write        : integer;
    variable v_read         : integer;
    variable v_cycles       : natural;
    variable v_delta        : natural;
    variable v_err_sample   : natural := 0;
    variable v_err_rom      : natural := 0;
    variable v_rom          : std_logic_vector(C_DW-1 downto 0);
    variable v_idata        : std_logic_vector(C_DW-1 downto 0);

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
    log(ID_SEQUENCER, "hwla : capture of an error in CPU1 on debug_uart_tx_o", C_TB_SCOPE);
    v_t0 := now;

    set_slv     (C_SW1, clk, switch);
    wait_value  (led0, C_SW1, cfg, "LED0 = switches");
    check_value (debug_uart_tx, '1', ERROR, "debug_uart_tx_o idle", C_TB_SCOPE);
    check_stable(debug_uart_tx, now - v_t0, ERROR, "debug_uart_tx_o : no capture without error", C_TB_SCOPE);

    -- New switches, then an error just after their write to LED0 : both in
    -- the capture
    set_slv     (C_SW2, clk, switch);
    wait_value  (led0, C_SW2, cfg, "LED0 = new switches");
    v_t_led  := now;
    -- Error until the difference flag : the capture is sent just after it
    wait until falling_edge(clk);
    inject(1) <= cfg.fault_on;
    if led_diff = "000"
    then
      wait until led_diff /= "000" for cfg.timeout;
    end if;
    v_t_diff := now;
    inject(1) <= not cfg.fault_on;
    check_value (led_diff /= "000", ERROR, "led_diff : difference flag of the error in CPU1", C_TB_SCOPE);
    v_cycles := (v_t_diff - v_t_led) / (cfg.clk_ratio * cfg.clk_period);
    log(ID_SEQUENCER_SUB, "Difference flag " & integer'image(v_cycles) & " cycles after the change of LED0", C_TB_SCOPE);

    -- Capture : DEPTH samples, a sample in C_SAMPLE_BYTES bytes from the
    -- LSB, then the first sample of the next capture (the difference flag
    -- stays set : a new capture after each extraction)
    v_uart.bit_time := C_BIT_TIME;
    for i in 0 to (C_DEPTH+1)*C_SAMPLE_BYTES-1 loop
      uart_receive(data_value     => v_byte,
                   msg            => "HWLA byte " & integer'image(i),
                   rx             => debug_uart_tx,
                   terminate_loop => uart_no_terminate,
                   config         => v_uart,
                   scope          => C_TB_SCOPE);
      v_capture(i / C_SAMPLE_BYTES)(8*(i mod C_SAMPLE_BYTES)+7 downto 8*(i mod C_SAMPLE_BYTES)) := v_byte;
    end loop;
    for s in 0 to C_DEPTH-1 loop
      log(ID_SEQUENCER_SUB, "HWLA sample " & integer'image(s) & " : " & to_hstring(v_capture(s)), C_TB_SCOPE);
    end loop;

    -- Data bus : first accepted write of the new switches to LED0, first
    -- read of the new switches after it (next loop iteration)
    v_write := -1;
    for s in C_DEPTH-1 downto 0 loop
      if (v_capture(s)(C_DCS) = '1') and (v_capture(s)(C_DWE) = '1') and (v_capture(s)(C_DREADY) = '1') and
         (field(v_capture(s), C_DADDR , 8) = C_LED0_DATA) and
         (field(v_capture(s), C_DWDATA, 8) = C_SW2)
      then
        v_write := s;
      end if;
    end loop;
    v_read := -1;
    for s in C_DEPTH-1 downto v_write+1 loop
      if (v_capture(s)(C_DCS) = '1') and (v_capture(s)(C_DRE) = '1') and (v_capture(s)(C_DREADY) = '1') and
         (field(v_capture(s), C_DADDR , 8) = C_SWITCH_DATA) and
         (field(v_capture(s), C_DRDATA, 8) = C_SW2)
      then
        v_read := s;
      end if;
    end loop;
    check_value(v_write >= 0 and v_write < C_PRE_TRIGGER, ERROR, "Sample " & integer'image(v_write) & " (before the trigger) : write of the new switches to LED0", C_TB_SCOPE);
    check_value(v_read  >= 0                            , ERROR, "Sample " & integer'image(v_read ) & " : read of the new switches after the write (next loop iteration)", C_TB_SCOPE);

    -- Trigger sample : sample PRE_TRIGGER
    if (v_write >= 0) and (C_TS_WIDTH > 0)
    then
      check_value(ts_delta(v_capture(C_PRE_TRIGGER), v_capture(v_write)), v_cycles + C_TRIGGER_DELAY, ERROR,
                  "Trigger sample " & integer'image(C_PRE_TRIGGER) & " : cycles after the write of LED0", C_TB_SCOPE);
    end if;

    -- Capture size : the next capture starts after the extraction of this
    -- one, not a few cycles after its last sample
    if C_TS_WIDTH > 0
    then
      check_value(ts_delta(v_capture(C_DEPTH), v_capture(C_DEPTH-1)) > 1000, ERROR,
                  "Next capture : first sample " & integer'image(ts_delta(v_capture(C_DEPTH), v_capture(C_DEPTH-1))) & " cycles (modulo 2**C_TS_WIDTH) after the capture", C_TB_SCOPE);
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
  end procedure;

end package body tb_PicoSoC_hwla_pkg;
