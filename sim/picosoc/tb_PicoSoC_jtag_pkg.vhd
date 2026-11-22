-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_jtag_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_jtag_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: JTAG helpers of the tb_PicoSoC scenarios, on the JTAG BFM of
--              asylum-verification-uvvm (jtag_bfm_pkg). The BFM scans one
--              TAP : the helpers scan the chain of PicoSoC_top (cfg.jtag),
--              with the other TAPs in BYPASS
--              * chain_ir : IR scan of every TAP (BYPASS but the target)
--              * chain_dr : DR scan of the target TAP, plus one BYPASS bit
--                per other TAP
--              The positions count from TDI : the first TAP after TDI is 0,
--              its bits are shifted in last (MSB of the vectors) and out
--              last
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-22  1.0      mrosiere Created
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

package tb_PicoSoC_jtag_pkg is

  constant C_JTAG_IR_IDCODE : std_logic_vector(PICOSOC_JTAG_IR_WIDTH-1 downto 0) := "00001";
  constant C_JTAG_IR_BYPASS : std_logic_vector(PICOSOC_JTAG_IR_WIDTH-1 downto 0) := "11111";

  -- BFM configuration for a chain of nb_tap TAPs : TCK 100 ns, IR scan of
  -- the IRs of every TAP
  function jtag_config
    (nb_tap   : positive
    ) return t_jtag_bfm_config;

  -- Chain of PicoSoC_top with the TAPs present (CPU debuggers, injection)
  function jtag_chain
    (user       : boolean
    ;supervisor : boolean
    ;inject     : boolean
    ) return t_jtag_chain;

  -- IDCODE of the TAP at the position tap of the chain
  impure function idcode
    (cfg      : t_tb_cfg
    ;tap      : natural
    ) return std_logic_vector;

  -- Capture-IR value of the chain ("00001" per TAP)
  function chain_ir_capture
    (nb_tap   : positive
    ) return std_logic_vector;

  -- Test-Logic-Reset (5 TCK with TMS = 1), then Run-Test/Idle
  procedure chain_reset
    (constant cfg      : in    t_tb_cfg
    ;signal   jtag_if  : inout t_jtag_if
    );

  -- IR scan : ir to the TAP tap, BYPASS to the others
  procedure chain_ir
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant ir       : in    std_logic_vector
    ;constant msg      : in    string
    ;signal   jtag_if  : inout t_jtag_if
    );

  -- DR scan of the TAP tap (the others in BYPASS) : data shifted in, the
  -- captured value of the same width in data_out
  procedure chain_dr
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant data     : in    std_logic_vector
    ;variable data_out : out   std_logic_vector
    ;constant msg      : in    string
    ;signal   jtag_if  : inout t_jtag_if
    );

end package tb_PicoSoC_jtag_pkg;

package body tb_PicoSoC_jtag_pkg is

  function jtag_config
    (nb_tap   : positive
    ) return t_jtag_bfm_config is
    variable v_config : t_jtag_bfm_config := C_JTAG_BFM_CONFIG_DEFAULT;
  begin
    v_config.tck_period  := 100 ns;
    v_config.ir_width    := PICOSOC_JTAG_IR_WIDTH*nb_tap;
    v_config.trst_enable := false;  -- No TRST* pad
    return v_config;
  end function;

  function jtag_chain
    (user       : boolean
    ;supervisor : boolean
    ;inject     : boolean
    ) return t_jtag_chain is
    variable v_chain : t_jtag_chain := (nb_tap => 0, user => -1, supervisor => -1, inject => -1);
  begin
    -- Chain order from TDI : user CPU, supervisor CPU, injection
    if user
    then
      v_chain.user       := v_chain.nb_tap;
      v_chain.nb_tap     := v_chain.nb_tap + 1;
    end if;
    if supervisor
    then
      v_chain.supervisor := v_chain.nb_tap;
      v_chain.nb_tap     := v_chain.nb_tap + 1;
    end if;
    if inject
    then
      v_chain.inject     := v_chain.nb_tap;
      v_chain.nb_tap     := v_chain.nb_tap + 1;
    end if;
    return v_chain;
  end function;

  impure function idcode
    (cfg      : t_tb_cfg
    ;tap      : natural
    ) return std_logic_vector is
  begin
    if tap = cfg.jtag.inject
    then
      return PICOSOC_JTAG_IDCODE_INJECT;
    end if;
    alert(TB_ERROR, "No TAP at position " & integer'image(tap), C_TB_SCOPE);
    return x"00000000";
  end function;

  function chain_ir_capture
    (nb_tap   : positive
    ) return std_logic_vector is
    variable v_ir : std_logic_vector(PICOSOC_JTAG_IR_WIDTH*nb_tap-1 downto 0);
  begin
    for i in 0 to nb_tap-1 loop
      v_ir(PICOSOC_JTAG_IR_WIDTH*(i+1)-1 downto PICOSOC_JTAG_IR_WIDTH*i) := C_JTAG_IR_IDCODE;
    end loop;
    return v_ir;
  end function;

  procedure chain_reset
    (constant cfg      : in    t_tb_cfg
    ;signal   jtag_if  : inout t_jtag_if
    ) is
  begin
    jtag_reset(msg     => "Test-Logic-Reset",
               jtag_if => jtag_if,
               scope   => C_TB_SCOPE,
               config  => jtag_config(cfg.jtag.nb_tap));
  end procedure;

  procedure chain_ir
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant ir       : in    std_logic_vector
    ;constant msg      : in    string
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    constant C_LAST    : natural := cfg.jtag.nb_tap-1;
    variable v_ir      : std_logic_vector(PICOSOC_JTAG_IR_WIDTH*cfg.jtag.nb_tap-1 downto 0);
  begin
    -- TAP p : bits of position C_LAST-p from the LSB
    for p in 0 to C_LAST loop
      v_ir(PICOSOC_JTAG_IR_WIDTH*(C_LAST-p+1)-1 downto PICOSOC_JTAG_IR_WIDTH*(C_LAST-p)) := ir when p = tap else C_JTAG_IR_BYPASS;
    end loop;
    jtag_write_ir(ir_value => v_ir,
                  msg      => msg,
                  jtag_if  => jtag_if,
                  scope    => C_TB_SCOPE,
                  config   => jtag_config(cfg.jtag.nb_tap));
  end procedure;

  procedure chain_dr
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant data     : in    std_logic_vector
    ;variable data_out : out   std_logic_vector
    ;constant msg      : in    string
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    -- BYPASS bits : tap before the target (MSB side), the others after it
    constant C_AFTER   : natural := cfg.jtag.nb_tap-1-tap;
    variable v_in      : std_logic_vector(data'length+cfg.jtag.nb_tap-1-1 downto 0) := (others => '0');
    variable v_out     : std_logic_vector(v_in'range);
  begin
    v_in(data'length+C_AFTER-1 downto C_AFTER) := data;
    jtag_scan_dr(data_value => v_in,
                 data_out   => v_out,
                 msg        => msg,
                 jtag_if    => jtag_if,
                 scope      => C_TB_SCOPE,
                 config     => jtag_config(cfg.jtag.nb_tap));
    data_out := v_out(data'length+C_AFTER-1 downto C_AFTER);
  end procedure;

end package body tb_PicoSoC_jtag_pkg;
