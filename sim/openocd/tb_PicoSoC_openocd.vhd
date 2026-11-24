-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_openocd
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_openocd.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: OpenOCD + GDB co-simulation of PicoSoC_top : OpenOCD (adapter
--              remote_bitbang, sim/openocd/remote_bitbang.cfg) drives the JTAG
--              chain through the UART pads, GDB runs sim/openocd/picosoc.py
--              (hooks rbb/cosim.sh of the co-simulation kit
--              asylum:verification:openocd)
--              DEBUG_MUX_SEL : function of the UART pads (debug_mux_sel_i)
--                "10" : JTAG pins, driven by rbb_jtag of the kit (PIN mode) :
--                       TCK = uart_rx_i, TDI = uart_tx_io, TMS =
--                       uart_rts_b_io, TDO = uart_cts_b_io ; one pin change
--                       every C_CLK_DIV clk_i cycles : TCK = FSYS_INT / 8
--                       (the limit of the TCK resynchronized in cpu_safety)
--                "11" : JTAG over the UART, the bytes of OpenOCD from rbb_axis
--                       of the kit (BYTE mode) sent on uart_rx_i, the answers
--                       received on uart_tx_io (UART VIP, JTAG_BAUD_RATE) ;
--                       an unknown TDO ('U' of a data read that no target
--                       answers) is sent as 1 by rbb_axis, with a warning
--              The firmware copies the switches to LED0. Before OpenOCD : the
--              firmware runs, no difference flag ; after OpenOCD quits : the
--              difference flag of CPU0 vs CPU1 raised by the injection of
--              the GDB scenario (INJECT), the firmware still runs (LED0
--              follows new switches). Error after C_COSIM_TIMEOUT.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-24  1.0      mrosiere Created
-- 2026-11-24  1.1      mrosiere Unknown TDO left to rbb_axis of the kit
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library bitvis_vip_uart;
use     bitvis_vip_uart.uart_bfm_pkg.all;

library asylum_uvvm;

library asylum;
use     asylum.PicoSoC_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

entity tb_PicoSoC_openocd is
  generic
    (FSYS                  : positive := 25_000_000
    ;FSYS_INT              : positive := 12_500_000
    ;JTAG_BAUD_RATE        : integer  := 921_600     -- JTAG over the UART pads (debug_mux_sel_i 11)
    ;SUPERVISOR            : boolean  := False
    ;USER_SAFETY           : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;USER_FAULT_INJECTION  : boolean  := True
    ;DEBUG_ENABLE          : boolean  := True
    ;USER_CPU_DEBUG_ENABLE       : boolean := True
    ;SUPERVISOR_CPU_DEBUG_ENABLE : boolean := False
    ;CPU_MODEL             : string   := "WardRV_fsm"

    -- TB Parameters
    ;DEBUG_MUX_SEL         : string   := "10"        -- "10" (JTAG pins) / "11" (JTAG over the UART)
    ;TB_WATCHDOG           : natural  := 200_000     -- Timeout of one wait (clk_i cycles)
     );
end entity tb_PicoSoC_openocd;

architecture tb of tb_PicoSoC_openocd is
  constant C_SCOPE          : string    := "TB_PICOSOC_OPENOCD";
  constant TB_PERIOD        : time      := (1e9 / FSYS) * 1 ns;
  constant C_TIMEOUT        : time      := TB_WATCHDOG * TB_PERIOD;
  -- OpenOCD + GDB session (simulated time)
  constant C_COSIM_TIMEOUT  : time      := 10 sec;

  -- TCK high and low C_CLK_DIV clk_i cycles each : 4 SoC clock cycles
  constant C_CLK_DIV        : positive  := 4 * FSYS / FSYS_INT;

  -- UART of JTAG over the UART (bit time of the DUT : FSYS_INT / JTAG_BAUD_RATE cycles)
  function bitbang_config return t_uart_bfm_config is
    variable v_config : t_uart_bfm_config := C_UART_BFM_CONFIG_DEFAULT;
  begin
    v_config.bit_time   := (FSYS_INT/JTAG_BAUD_RATE) * (1 sec / FSYS_INT);
    v_config.parity     := PARITY_NONE;
    v_config.timeout    := 0 ns;  -- the answers come when OpenOCD sends 'R'
    v_config.id_for_bfm := ID_NEVER;
    return v_config;
  end function;

  constant C_BITBANG        : t_uart_bfm_config := bitbang_config;

  -- Switches copied to LED0 by the firmware, before and after OpenOCD
  constant C_SW1            : std_logic_vector(8-1 downto 0) := x"5A";
  constant C_SW2            : std_logic_vector(8-1 downto 0) := x"A5";

  -- =====[ Dut Signals ]=========================
  signal  clk_i             : std_logic := '0';
  signal  clk_ena           : boolean   := true;
  signal  arst_i            : std_logic := '1';             -- RESET_POLARITY high
  signal  switch_i          : std_logic_vector(8-1 downto 0) := (others => '0');
  signal  debug_mux_sel_i   : std_logic_vector(2-1 downto 0) := C_MUX_UART;
  signal  led0_o            : std_logic_vector(8-1 downto 0);
  signal  led1_o            : std_logic_vector(8-1 downto 0);
  signal  led_diff_o        : std_logic_vector(3-1 downto 0);
  signal  uart_rx_i         : std_logic;
  signal  uart_tx_io        : std_logic;
  signal  uart_cts_b_io     : std_logic;
  signal  uart_rts_b_io     : std_logic;
  signal  spi_sclk_io       : std_logic;
  signal  spi_cs_b_io       : std_logic;
  signal  spi_io_io         : std_logic_vector(8-1 downto 0);
  signal  i2c_scl_io        : std_logic;
  signal  i2c_sda_io        : std_logic;

  -- =====[ OpenOCD ]=============================
  signal  rbb_start         : std_logic := '0';   -- the firmware runs : OpenOCD may connect
  signal  quit              : std_logic := '0';   -- OpenOCD quit
  -- JTAG pins (debug_mux_sel_i 10)
  signal  tck               : std_logic;
  signal  tms               : std_logic;
  signal  tdi               : std_logic;
  -- Bytes of OpenOCD and answers (debug_mux_sel_i 11)
  signal  uart_rx           : std_logic := '1';
  signal  cmd_tdata         : std_logic_vector(8-1 downto 0);
  signal  cmd_tvalid        : std_logic;
  signal  cmd_tready        : std_logic := '0';
  signal  ans_tdata         : std_logic_vector(8-1 downto 0) := (others => '0');
  signal  ans_tvalid        : std_logic := '0';
  signal  uart_stop         : std_logic := '0';

begin  -- architecture tb

  -----------------------------------------------------------------------------
  -- Design Under Test
  -----------------------------------------------------------------------------
  dut : PicoSoC_top
    generic map
    (FSYS                  => FSYS
    ,FSYS_INT              => FSYS_INT
    ,JTAG_BAUD_RATE        => JTAG_BAUD_RATE
    ,RESET_POLARITY        => "high"
    ,DEBUG_ENABLE          => DEBUG_ENABLE
    ,USER_CPU_DEBUG_ENABLE       => USER_CPU_DEBUG_ENABLE
    ,SUPERVISOR_CPU_DEBUG_ENABLE => SUPERVISOR_CPU_DEBUG_ENABLE
    ,SUPERVISOR            => SUPERVISOR
    ,USER_SAFETY           => USER_SAFETY
    ,USER_FAULT_INJECTION  => USER_FAULT_INJECTION
    ,USER_IT_POLARITY      => "high"
    ,USER_FAULT_POLARITY   => "high"
    ,CPU_MODEL             => CPU_MODEL
     )
    port map
    (clk_i            => clk_i
    ,arst_i           => arst_i
    ,switch_i         => switch_i
    ,debug_mux_sel_i  => debug_mux_sel_i
    ,led0_o           => led0_o
    ,led1_o           => led1_o
    ,led_diff_o       => led_diff_o
    ,it_user_i        => '0'
    ,inject_error_i   => "000"
    ,uart_rx_i        => uart_rx_i
    ,uart_tx_io       => uart_tx_io
    ,uart_cts_b_io    => uart_cts_b_io
    ,uart_rts_b_io    => uart_rts_b_io
    ,spi_sclk_io      => spi_sclk_io
    ,spi_cs_b_io      => spi_cs_b_io
    ,spi_io_io        => spi_io_io
    ,i2c_scl_io       => i2c_scl_io
    ,i2c_sda_io       => i2c_sda_io
    ,pwm_o            => open
    ,debug_uart_tx_o  => open
    );

  -- Pull-ups of the pads
  spi_sclk_io   <= 'H';
  spi_cs_b_io   <= 'H';
  spi_io_io     <= (others => 'H');
  i2c_scl_io    <= 'H';
  i2c_sda_io    <= 'H';
  uart_tx_io    <= 'H';
  uart_cts_b_io <= 'H';
  uart_rts_b_io <= 'H';

  clock_generator(clk_i, clk_ena, TB_PERIOD, "TB Clock");

  -----------------------------------------------------------------------------
  -- debug_mux_sel_i 10 : OpenOCD drives the JTAG pins (PIN mode of the kit)
  -----------------------------------------------------------------------------
  gen_jtag:
  if DEBUG_MUX_SEL = "10"
  generate
    ins_rbb : entity asylum_uvvm.rbb_jtag
      generic map
      (CLK_DIV         => C_CLK_DIV
      )
      port map
      (clk_i           => clk_i
      ,arst_b_i        => rbb_start
      ,tck_o           => tck
      ,tms_o           => tms
      ,tdi_o           => tdi
      ,trst_b_o        => open                             -- reset_config none
      ,srst_b_o        => open
      ,tdo_i           => uart_cts_b_io                    -- 'H' out of the shifts
      ,quit_o          => quit
      );

    uart_rx_i     <= tck;
    uart_tx_io    <= tdi;
    uart_rts_b_io <= tms;
  end generate gen_jtag;

  -----------------------------------------------------------------------------
  -- debug_mux_sel_i 11 : the bytes of OpenOCD (BYTE mode of the kit) on the
  -- UART, its answers from the UART
  -----------------------------------------------------------------------------
  gen_bitbang:
  if DEBUG_MUX_SEL = "11"
  generate
    ins_rbb : entity asylum_uvvm.rbb_axis
      port map
      (clk_i           => clk_i
      ,arst_b_i        => rbb_start
      ,m_axis_tdata_o  => cmd_tdata
      ,m_axis_tvalid_o => cmd_tvalid
      ,m_axis_tready_i => cmd_tready
      ,s_axis_tdata_i  => ans_tdata
      ,s_axis_tvalid_i => ans_tvalid
      ,s_axis_tready_o => open
      ,quit_o          => quit
      );

    uart_rx_i <= uart_rx;

    -- Bytes of OpenOCD : one taken at a time, sent on RX
    p_cmd : process
      variable v_byte : std_logic_vector(8-1 downto 0);
    begin
      wait until rising_edge(clk_i) and cmd_tvalid = '1';
      v_byte     := cmd_tdata;
      cmd_tready <= '1';
      wait until rising_edge(clk_i);
      cmd_tready <= '0';
      uart_transmit(data_value     => v_byte,
                    msg            => "byte of OpenOCD",
                    tx             => uart_rx,
                    config         => C_BITBANG,
                    scope          => C_SCOPE);
    end process;

    -- Answers to 'R' received on TX, given to OpenOCD
    p_ans : process
      variable v_byte : std_logic_vector(8-1 downto 0);
    begin
      if not (rbb_start = '1' and to_X01(uart_tx_io) = '1')
      then
        wait until rbb_start = '1' and to_X01(uart_tx_io) = '1';  -- idle line
      end if;
      uart_receive(data_value     => v_byte,
                   msg            => "answer to 'R'",
                   rx             => uart_tx_io,
                   terminate_loop => uart_stop,
                   config         => C_BITBANG,
                   scope          => C_SCOPE);
      -- x30 or x31 : bit 0 is TDO, an unknown one is sent as 1 by rbb_axis
      if v_byte(8-1 downto 1) /= "0011000"
      then
        alert(ERROR, "Answer x" & to_hstring(v_byte) & " to 'R' is not '0' or '1'", C_SCOPE);
      end if;
      wait until rising_edge(clk_i);
      ans_tdata  <= v_byte;
      ans_tvalid <= '1';
      wait until rising_edge(clk_i);
      ans_tvalid <= '0';
    end process;
  end generate gen_bitbang;

  -----------------------------------------------------------------------------
  -- Sequencer
  -----------------------------------------------------------------------------
  p_main : process
  begin
    log(ID_LOG_HDR, "OpenOCD + GDB co-simulation, debug_mux_sel_i " & DEBUG_MUX_SEL & " : CPU_MODEL = " & CPU_MODEL &
                    ", SUPERVISOR = " & boolean'image(SUPERVISOR) & ", USER_SAFETY = " & USER_SAFETY, C_SCOPE);
    if DEBUG_MUX_SEL /= "10" and DEBUG_MUX_SEL /= "11"
    then
      alert(TB_ERROR, "DEBUG_MUX_SEL """ & DEBUG_MUX_SEL & """ : 10 (JTAG pins) or 11 (JTAG over the UART)", C_SCOPE);
    end if;

    -- Reset, UART pads to the debugger, the firmware runs
    debug_mux_sel_i <= C_MUX_JTAG when DEBUG_MUX_SEL = "10" else C_MUX_BITBANG;
    switch_i        <= C_SW1;
    do_reset(active => '1', clk => clk_i, arst => arst_i);
    await_value(led0_o, C_SW1, 0 ns, C_TIMEOUT, ERROR, "LED0 = switches 0x" & to_hstring(C_SW1) & " : the firmware runs", C_SCOPE);
    check_value(led_diff_o, "000", ERROR, "led_diff : no difference before OpenOCD", C_SCOPE);

    -- OpenOCD + GDB (picosoc.py)
    rbb_start <= '1';
    wait until quit = '1' for C_COSIM_TIMEOUT;
    if quit /= '1'
    then
      alert(TB_ERROR, "Timeout : OpenOCD still connected", C_SCOPE);
    end if;
    log(ID_LOG_HDR, "OpenOCD quit at " & integer'image(now / 1 us) & " us", C_SCOPE);

    -- Seen by the testbench after the debug session
    check_value(led_diff_o, "001", ERROR, "led_diff : CPU0 vs CPU1, error injected in CPU1 by OpenOCD (INJECT)", C_SCOPE);
    set_slv    (C_SW2, clk_i, switch_i);
    await_value(led0_o, C_SW2, 0 ns, C_TIMEOUT, ERROR, "LED0 = switches 0x" & to_hstring(C_SW2) & " : the firmware runs after the debug session", C_SCOPE);

    report_alert_counters(FINAL);
    std.env.stop;
    wait;
  end process;

end architecture tb;
