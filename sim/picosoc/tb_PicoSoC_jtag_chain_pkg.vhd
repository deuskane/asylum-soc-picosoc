-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_jtag_chain_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_jtag_chain_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario jtag_chain of tb_PicoSoC, from reset (at least one
--              TAP) : the JTAG chain on the UART pads (switches 10)
--              * TDO not driven out of a scan
--              * after Test-Logic-Reset, one DR scan reads the IDCODE of
--                every TAP of the chain, in the chain order
--              * every TAP in BYPASS : a DR scan is delayed by one bit per
--                TAP
--              * IDCODE of each TAP alone, the others in BYPASS (position of
--                each TAP)
--              The Capture-IR value of the whole chain ("00001" per TAP) is
--              checked on every IR scan by the monitor of tb_PicoSoC
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-22  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere Target TAP with the chain fields of the BFM
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

package tb_PicoSoC_jtag_chain_pkg is

  -- IDCODEs, BYPASS length and position of the TAPs of the chain
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   tdo_pad  : in    std_logic
    ;signal   jtag_if  : inout t_jtag_if
    );

end package tb_PicoSoC_jtag_chain_pkg;

package body tb_PicoSoC_jtag_chain_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   tdo_pad  : in    std_logic
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    constant C_NB      : positive := cfg.jtag.nb_tap;
    constant C_SW      : std_logic_vector(8-1 downto 0) := x"80";  -- MSBs 10 : JTAG
    constant C_PATTERN : std_logic_vector(16-1 downto 0) := x"B4E3";
    variable v_ids     : std_logic_vector(32*C_NB-1 downto 0);
    variable v_exp     : std_logic_vector(32*C_NB-1 downto 0);
    variable v_id      : std_logic_vector(32-1 downto 0);
    variable v_ir      : std_logic_vector(PICOSOC_JTAG_IR_WIDTH*C_NB-1 downto 0) := (others => '1');
    variable v_zero    : std_logic_vector(C_NB-1 downto 0) := (others => '0');
    variable v_bypass  : std_logic_vector(16+C_NB-1 downto 0);
  begin
    log(ID_SEQUENCER, "jtag_chain : " & integer'image(C_NB) & " TAP(s) on the UART pads", C_TB_SCOPE);

    set_slv    (C_SW, clk, switch);
    wait_value (led0, C_SW, cfg, "LED0 = switches 0x" & to_hstring(C_SW) & " : UART pads to JTAG");
    check_value(tdo_pad = 'H', ERROR, "TDO not driven out of a scan", C_TB_SCOPE);

    -- IDCODE of every TAP (the first TAP after TDI in the MSBs)
    for p in 0 to C_NB-1 loop
      v_exp(32*(C_NB-p)-1 downto 32*(C_NB-1-p)) := idcode(cfg, p);
    end loop;
    chain_reset (cfg, jtag_if);
    jtag_scan_dr(data_value => v_exp xor v_exp,
                 data_out   => v_ids,
                 msg        => "IDCODE of every TAP",
                 jtag_if    => jtag_if,
                 scope      => C_TB_SCOPE,
                 config     => jtag_config(C_NB));
    check_value(v_ids, v_exp, ERROR, "IDCODE of every TAP after Test-Logic-Reset, in the chain order", C_TB_SCOPE);
    check_value(tdo_pad = 'H', ERROR, "TDO not driven after the scan", C_TB_SCOPE);

    -- Every TAP in BYPASS : one bit (captured 0) per TAP
    jtag_write_ir(ir_value => v_ir,
                  msg      => "BYPASS",
                  jtag_if  => jtag_if,
                  scope    => C_TB_SCOPE,
                  config   => jtag_config(C_NB));
    jtag_scan_dr(data_value => not v_zero & C_PATTERN,
                 data_out   => v_bypass,
                 msg        => "BYPASS",
                 jtag_if    => jtag_if,
                 scope      => C_TB_SCOPE,
                 config     => jtag_config(C_NB));
    check_value(v_bypass, C_PATTERN & v_zero, ERROR, "BYPASS : one bit per TAP", C_TB_SCOPE);

    -- IDCODE of each TAP alone : position of the TAP in the chain
    for p in 0 to C_NB-1 loop
      jtag_write_ir(ir_value => C_JTAG_IR_IDCODE, msg => "IDCODE of TAP " & integer'image(p), jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, p));
      jtag_scan_dr (data_value => x"00000000", data_out => v_id, msg => "IDCODE of TAP " & integer'image(p), jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, p));
      check_value(v_id, idcode(cfg, p), ERROR, "IDCODE of TAP " & integer'image(p) & ", the others in BYPASS", C_TB_SCOPE);
    end loop;
  end procedure;

end package body tb_PicoSoC_jtag_chain_pkg;
