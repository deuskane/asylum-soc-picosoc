-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_jtag_last_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_jtag_last_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: Scenario jtag_last of tb_PicoSoC, from reset (user*, debug
--              unit of the user CPU) : TDO when the last stages of the JTAG
--              chain have no TAP (wires : TDO = TDI, enable of the stage
--              ORed with the enables before it), as in the configuration of
--              the board (no supervisor, no DEBUG_ENABLE)
--              * switches 10 (JTAG pads) : TDO pad not driven out of a scan ;
--                the IDCODE of every TAP in one DR scan, each bit driven by
--                the SoC on the TDO pad (no 'H' of the pull-up) ; dmactive,
--                then dmstatus of the user CPU read through the DMI
--              * switches 11 (JTAG over the UART) : the IDCODE of every TAP,
--                dmstatus of the user CPU (jtag_bitbang answers '1' when
--                TDO is not driven)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;

library asylum;
use     asylum.WardRV_debug_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;
use     work.tb_PicoSoC_jtag_pkg.all;
use     work.tb_PicoSoC_bitbang_pkg.all;

package tb_PicoSoC_jtag_last_pkg is

  -- IDCODEs and dmstatus through the JTAG pads and JTAG over the UART
  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   tdo_pad  : in    std_logic
    ;signal   jtag_if  : inout t_jtag_if
    ;signal   uart_rx  : inout std_logic
    ;signal   bitbang  : in    t_bitbang_rsp
    );

end package tb_PicoSoC_jtag_last_pkg;

package body tb_PicoSoC_jtag_last_pkg is

  procedure run
    (constant cfg      : in    t_tb_cfg
    ;signal   clk      : in    std_logic
    ;signal   switch   : out   std_logic_vector
    ;signal   led0     : in    std_logic_vector
    ;signal   tdo_pad  : in    std_logic
    ;signal   jtag_if  : inout t_jtag_if
    ;signal   uart_rx  : inout std_logic
    ;signal   bitbang  : in    t_bitbang_rsp
    ) is
    constant C_NB      : positive := cfg.jtag.nb_tap;
    constant C_TAP     : natural  := cfg.jtag.user;
    constant C_SW10    : std_logic_vector(8-1 downto 0) := x"8C";  -- MSBs 10 : JTAG pads
    constant C_SW11    : std_logic_vector(8-1 downto 0) := x"C9";  -- MSBs 11 : JTAG over the UART
    variable v_ids     : std_logic_vector(32*C_NB-1 downto 0);
    variable v_exp     : std_logic_vector(32*C_NB-1 downto 0);
    variable v_data    : std_logic_vector(32-1 downto 0);
  begin
    log(ID_SEQUENCER, "jtag_last : " & integer'image(C_NB) & " TAP(s), TDO through the stages without TAP", C_TB_SCOPE);

    for p in 0 to C_NB-1 loop
      v_exp(32*(C_NB-p)-1 downto 32*(C_NB-1-p)) := idcode(cfg, p);
    end loop;

    -- Switches 10 : JTAG pads
    set_slv     (C_SW10, clk, switch);
    wait_value  (led0, C_SW10, cfg, "LED0 = switches 0x" & to_hstring(C_SW10) & " : UART pads to JTAG");
    check_value (tdo_pad = 'H', ERROR, "TDO pad not driven out of a scan", C_TB_SCOPE);
    chain_reset (cfg, jtag_if);
    jtag_scan_dr(data_value => v_exp xor v_exp,
                 data_out   => v_ids,
                 msg        => "IDCODE of every TAP",
                 jtag_if    => jtag_if,
                 scope      => C_TB_SCOPE,
                 config     => jtag_config(C_NB));
    check_value (v_ids, v_exp, ERROR, "IDCODE of every TAP through the JTAG pads", C_TB_SCOPE);
    -- An undriven TDO pad reads 'H' (pull-up of the testbench)
    check_value (v_ids = to_X01(v_ids), ERROR, "TDO pad driven by the SoC during Shift-DR", C_TB_SCOPE);
    dmi_write   (cfg, C_TAP, DM_DMCONTROL, x"00000001", jtag_if);                  -- dmactive
    dmi_read    (cfg, C_TAP, DM_DMSTATUS, v_data, jtag_if);
    check_value (v_data(11 downto 8), "1100", ERROR, "dmstatus of the user CPU through the JTAG pads : allrunning", C_TB_SCOPE);

    -- Switches 11 : JTAG over the UART
    set_slv         (C_SW11, clk, switch);
    wait_value      (led0, C_SW11, cfg, "LED0 = switches 0x" & to_hstring(C_SW11) & " : UART pads to JTAG over the UART");
    bitbang_reset   (cfg, uart_rx);
    bitbang_scan_dr (v_exp xor v_exp, v_ids, "IDCODE of every TAP", cfg, uart_rx, bitbang, jtag_config(C_NB));
    check_value     (v_ids, v_exp, ERROR, "IDCODE of every TAP through JTAG over the UART", C_TB_SCOPE);
    bitbang_write_ir(JTAG_IR_DMI, "dmi", cfg, uart_rx, bitbang, jtag_config(cfg, C_TAP));
    bitbang_dmi     (DMI_OP_READ, DM_DMSTATUS, x"00000000", v_data, cfg, C_TAP, uart_rx, bitbang);
    check_value     (v_data(11 downto 8), "1100", ERROR, "dmstatus of the user CPU through JTAG over the UART : allrunning", C_TB_SCOPE);
  end procedure;

end package body tb_PicoSoC_jtag_last_pkg;
