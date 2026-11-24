-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_bitbang_chain_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_bitbang_chain_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario bitbang_chain of tb_PicoSoC, from reset (at least one
--              TAP) : the JTAG chain through JTAG over the UART pads
--              (debug_mux_sel_i 11, remote_bitbang bytes on uart_rx_i, answers on
--              the TX pad)
--              * after Test-Logic-Reset, one DR scan reads the IDCODE of
--                every TAP of the chain, in the chain order
--              * every TAP in BYPASS : a DR scan is delayed by one bit per
--                TAP
--              * IDCODE of each TAP alone, the others in BYPASS (position of
--                each TAP)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere UART pads to JTAG over the UART with
--                               debug_mux_sel_i (was the switch MSBs) :
--                               switches 0x03
-- 2026-11-24  1.2      mrosiere remote_bitbang BFM rbb_bfm_pkg (rbb_if, answers
--                               t_rbb_answers)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum_uvvm;
use     asylum_uvvm.rbb_bfm_pkg.all;

library asylum;
use     asylum.PicoSoC_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;
use     work.tb_PicoSoC_bitbang_pkg.all;

package tb_PicoSoC_bitbang_chain_pkg is

  -- IDCODEs, BYPASS length and position of the TAPs of the chain
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   rbb_if   : inout t_rbb_if
    ;signal   bitbang  : in    t_rbb_answers
    );

end package tb_PicoSoC_bitbang_chain_pkg;

package body tb_PicoSoC_bitbang_chain_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   mux_sel  : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   rbb_if   : inout t_rbb_if
    ;signal   bitbang  : in    t_rbb_answers
    ) is
    constant C_NB      : positive := cfg.jtag.nb_tap;
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"03";
    constant C_PATTERN : std_logic_vector(16-1 downto 0) := x"B4E3";
    variable v_ids     : std_logic_vector(32*C_NB-1 downto 0);
    variable v_exp     : std_logic_vector(32*C_NB-1 downto 0);
    variable v_id      : std_logic_vector(32-1 downto 0);
    variable v_ir      : std_logic_vector(PICOSOC_JTAG_IR_WIDTH*C_NB-1 downto 0) := (others => '1');
    variable v_zero    : std_logic_vector(C_NB-1 downto 0) := (others => '0');
    variable v_bypass  : std_logic_vector(16+C_NB-1 downto 0);
  begin
    log(ID_SEQUENCER, "bitbang_chain : " & integer'image(C_NB) & " TAP(s) through JTAG over the UART pads", C_TB_SCOPE);

    set_slv    (C_MUX_BITBANG, clk, mux_sel);
    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches 0x" & to_hstring(C_SW) & " : UART pads to JTAG over the UART");

    -- IDCODE of every TAP (the first TAP after TDI in the MSBs)
    for p in 0 to C_NB-1 loop
      v_exp(32*(C_NB-p)-1 downto 32*(C_NB-1-p)) := idcode(cfg, p);
    end loop;
    bitbang_reset   (cfg, clk, rbb_if);
    bitbang_scan_dr (v_exp xor v_exp, v_ids, "IDCODE of every TAP", cfg, clk, rbb_if, bitbang, jtag_config(C_NB));
    check_value     (v_ids, v_exp, ERROR, "IDCODE of every TAP after Test-Logic-Reset, in the chain order (JTAG over the UART)", C_TB_SCOPE);

    -- Every TAP in BYPASS : one bit (captured 0) per TAP
    bitbang_write_ir(v_ir, "BYPASS", cfg, clk, rbb_if, bitbang, jtag_config(C_NB));
    bitbang_scan_dr (not v_zero & C_PATTERN, v_bypass, "BYPASS", cfg, clk, rbb_if, bitbang, jtag_config(C_NB));
    check_value     (v_bypass, C_PATTERN & v_zero, ERROR, "BYPASS : one bit per TAP (JTAG over the UART)", C_TB_SCOPE);

    -- IDCODE of each TAP alone : position of the TAP in the chain
    for p in 0 to C_NB-1 loop
      bitbang_write_ir(C_JTAG_IR_IDCODE, "IDCODE of TAP " & integer'image(p), cfg, clk, rbb_if, bitbang, jtag_config(cfg, p));
      bitbang_scan_dr (x"00000000", v_id, "IDCODE of TAP " & integer'image(p), cfg, clk, rbb_if, bitbang, jtag_config(cfg, p));
      check_value     (v_id, idcode(cfg, p), ERROR, "IDCODE of TAP " & integer'image(p) & ", the others in BYPASS (JTAG over the UART)", C_TB_SCOPE);
    end loop;
  end procedure;

end package body tb_PicoSoC_bitbang_chain_pkg;
