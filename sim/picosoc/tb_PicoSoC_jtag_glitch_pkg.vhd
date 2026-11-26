-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_jtag_glitch_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_jtag_glitch_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario jtag_glitch of tb_PicoSoC, from reset (at least one
--              TAP) : the JTAG chain on the UART pads (debug_mux_sel_i 10)
--              with a TCK that bounces, as a ringing cable
--              * after Test-Logic-Reset, a DR scan of the IDCODE of every TAP
--                where both edges of TCK bounce on every shifted bit but the
--                last (TCK back to its old level, then to the new one, the
--                whole bounce shorter than half a SoC clock period) : the
--                IDCODEs are read, in the chain order
--              * then, without bounce, an IR scan (IDCODE in every TAP, the
--                Capture-IR value of the whole chain checked by the monitor
--                of tb_PicoSoC) and a DR scan read the IDCODEs again : every
--                TAP kept its state
--              Every TAP resynchronizes TCK on the SoC clock : a bounce
--              shorter than a clock period gives one edge. A TAP clocked by
--              the TCK pad sees two edges per bounce and shifts too many bits.
--              The bounces stay in Shift-DR (TMS 0) : the extra edges seen by
--              the Capture-IR monitor (jtag_if.tck) do not change its state
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-26  1.0      mrosiere Created
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

package tb_PicoSoC_jtag_glitch_pkg is

  -- IDCODEs of the chain read with a bouncing TCK
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    );

end package tb_PicoSoC_jtag_glitch_pkg;

package body tb_PicoSoC_jtag_glitch_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    constant C_NB      : positive := cfg.jtag.nb_tap;
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"5C";
    constant C_HALF    : time     := jtag_config(C_NB).tck_period/2;
    -- Each step of a bounce : a quarter of the SoC clock period
    constant C_BOUNCE  : time     := cfg.clk_period * cfg.clk_ratio / 4;
    variable v_ids     : std_logic_vector(32*C_NB-1 downto 0);
    variable v_exp     : std_logic_vector(32*C_NB-1 downto 0);
    variable v_ir      : std_logic_vector(PICOSOC_JTAG_IR_WIDTH*C_NB-1 downto 0);

    -- One TCK cycle as jtag_clock of the BFM (TCK falls with the new TMS and
    -- TDI, TDO sampled just before the rising edge), each edge followed by
    -- a bounce when bounce is true
    procedure clock
      (constant tms    : in    std_logic
      ;constant bounce : in    boolean
      ;variable tdo    : out   std_logic
      ;signal   jif    : inout t_jtag_if
      ) is
    begin
      jif.tck <= '0';
      jif.tms <= tms;
      jif.tdi <= '0';
      if bounce
      then
        wait for C_BOUNCE; jif.tck <= '1';
        wait for C_BOUNCE; jif.tck <= '0';
        wait for C_HALF - 2*C_BOUNCE;
      else
        wait for C_HALF;
      end if;
      tdo     := jif.tdo;
      jif.tck <= '1';
      if bounce
      then
        wait for C_BOUNCE; jif.tck <= '0';
        wait for C_BOUNCE; jif.tck <= '1';
        wait for C_HALF - 2*C_BOUNCE;
      else
        wait for C_HALF;
      end if;
    end procedure;

    variable v_tdo     : std_logic;
  begin
    log(ID_SEQUENCER, "jtag_glitch : " & integer'image(C_NB) & " TAP(s), TCK bounces of 2 x " & integer'image(C_BOUNCE / 1 ps) & " ps", C_TB_SCOPE);

    set_slv    (C_MUX_JTAG, clk, mux_sel);
    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches 0x" & to_hstring(C_SW) & " : UART pads to JTAG");

    -- IDCODE of every TAP (the first TAP after TDI in the MSBs)
    for p in 0 to C_NB-1 loop
      v_exp(32*(C_NB-p)-1 downto 32*(C_NB-1-p)) := idcode(cfg, p);
    end loop;
    chain_reset(cfg, jtag_if);

    -- Run-Test/Idle -> Select-DR-Scan -> Capture-DR -> Shift-DR, the bits
    -- (bounces on all but the last one, TMS 1 -> Exit1-DR), Update-DR,
    -- Run-Test/Idle
    clock('1', false, v_tdo, jtag_if);
    clock('0', false, v_tdo, jtag_if);
    clock('0', false, v_tdo, jtag_if);
    for i in 0 to 32*C_NB-1 loop
      if i = 32*C_NB-1
      then
        clock('1', false, v_ids(i), jtag_if);
      else
        clock('0', true , v_ids(i), jtag_if);
      end if;
    end loop;
    clock('1', false, v_tdo, jtag_if);
    clock('0', false, v_tdo, jtag_if);
    check_value(v_ids, v_exp, ERROR, "IDCODE of every TAP read with TCK bounces, in the chain order", C_TB_SCOPE);

    -- Without bounce : IR scan (Capture-IR monitor), IDCODEs again
    for p in 0 to C_NB-1 loop
      v_ir(PICOSOC_JTAG_IR_WIDTH*(p+1)-1 downto PICOSOC_JTAG_IR_WIDTH*p) := C_JTAG_IR_IDCODE;
    end loop;
    jtag_write_ir(ir_value => v_ir,
                  msg      => "IDCODE",
                  jtag_if  => jtag_if,
                  scope    => C_TB_SCOPE,
                  config   => jtag_config(C_NB));
    jtag_scan_dr(data_value => v_exp xor v_exp,
                 data_out   => v_ids,
                 msg        => "IDCODE of every TAP",
                 jtag_if    => jtag_if,
                 scope      => C_TB_SCOPE,
                 config     => jtag_config(C_NB));
    check_value(v_ids, v_exp, ERROR, "IDCODE of every TAP after the bounces : every TAP kept its state", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_jtag_glitch_pkg;
