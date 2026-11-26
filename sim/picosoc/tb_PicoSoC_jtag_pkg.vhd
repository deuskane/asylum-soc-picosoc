-------------------------------------------------------------------------------
-- Title      : tb_PicoSoC_jtag_pkg
-- Project    : PicoSoC
-------------------------------------------------------------------------------
-- File       : tb_PicoSoC_jtag_pkg.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: JTAG helpers of the tb_PicoSoC scenarios, on the JTAG BFM of
--              asylum-verification-uvvm (jtag_bfm_pkg)
--              * jtag_config(cfg, tap) : BFM configuration of the TAP tap of
--                the chain of PicoSoC_top (cfg.jtag), the other TAPs in
--                BYPASS (head : the TAPs between the target and TDO, tail :
--                the TAPs between TDI and the target, as SVF HIR / TIR /
--                HDR / TDR)
--              * jtag_config(nb_tap) : the whole chain as one target (IR of
--                every TAP, Capture-IR monitor)
--              The positions count from TDI : the first TAP after TDI is 0,
--              its bits are shifted in last (MSB of the vectors) and out
--              last
--              * RISC-V DTM of a CPU debugger (WardRV_debug) : dtmcs and dmi
--                scans, DMI read / write with the busy retry of a debugger
--                (as WardRV_vips of asylum-processor-WardRV, on the chain)
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-22  1.0      mrosiere Created
-- 2026-11-23  1.1      mrosiere TCK 1 us (resynchronized in cpu_safety), one
--                               user CPU TAP per cluster
-- 2026-11-23  1.2      mrosiere Chain fields of the BFM (asylum:verification:
--                               uvvm 1.2.0) : chain_ir / chain_dr removed
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library uvvm_util;
context uvvm_util.uvvm_util_context;

library asylum_uvvm;
use     asylum_uvvm.jtag_bfm_pkg.all;

library asylum;
use     asylum.PicoSoC_pkg.all;
use     asylum.WardRV_debug_pkg.all;

library work;
use     work.tb_PicoSoC_bfm_pkg.all;

package tb_PicoSoC_jtag_pkg is

  constant C_JTAG_IR_IDCODE : std_logic_vector(PICOSOC_JTAG_IR_WIDTH-1 downto 0) := "00001";

  -- BFM configuration of a chain of nb_tap TAPs scanned as one target : TCK
  -- 1 us, IR of every TAP
  function jtag_config
    (nb_tap   : positive
    ) return t_jtag_bfm_config;

  -- BFM configuration of the TAP tap of the chain of cfg : TCK 1 us, its
  -- IR, the other TAPs in BYPASS (head and tail bits)
  function jtag_config
    (cfg      : t_tb_cfg
    ;tap      : natural
    ) return t_jtag_bfm_config;

  -- Chain of PicoSoC_top with the TAPs present (CPU debuggers of nb_user
  -- clusters, supervisor CPU debugger, injection)
  function jtag_chain
    (nb_user    : natural
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

  -- dtmcs of the CPU debugger at the position tap : data written, the read
  -- value in data_out
  procedure dtmcs_scan
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant data     : in    std_logic_vector(32-1 downto 0)
    ;variable data_out : out   std_logic_vector(32-1 downto 0)
    ;signal   jtag_if  : inout t_jtag_if
    );

  -- DMI write / read of the Debug Module of the CPU debugger at the
  -- position tap
  procedure dmi_write
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant addr     : in    std_logic_vector(DMI_ABITS-1 downto 0)
    ;constant data     : in    std_logic_vector(32-1 downto 0)
    ;signal   jtag_if  : inout t_jtag_if
    );

  procedure dmi_read
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant addr     : in    std_logic_vector(DMI_ABITS-1 downto 0)
    ;variable data     : out   std_logic_vector(32-1 downto 0)
    ;signal   jtag_if  : inout t_jtag_if
    );

end package tb_PicoSoC_jtag_pkg;

package body tb_PicoSoC_jtag_pkg is

  function jtag_config
    (nb_tap   : positive
    ) return t_jtag_bfm_config is
    variable v_config : t_jtag_bfm_config := C_JTAG_BFM_CONFIG_DEFAULT;
  begin
    -- TCK resynchronized on the SoC clock in PicoSoC_top : slow against it
    v_config.tck_period  := 1 us;
    v_config.ir_width    := PICOSOC_JTAG_IR_WIDTH*nb_tap;
    v_config.trst_enable := false;  -- No TRST* pad
    return v_config;
  end function;

  function jtag_config
    (cfg      : t_tb_cfg
    ;tap      : natural
    ) return t_jtag_bfm_config is
    variable v_config : t_jtag_bfm_config := jtag_config(1);
  begin
    v_config.head_ir := PICOSOC_JTAG_IR_WIDTH*(cfg.jtag.nb_tap-1-tap);
    v_config.tail_ir := PICOSOC_JTAG_IR_WIDTH*tap;
    v_config.head_dr := cfg.jtag.nb_tap-1-tap;
    v_config.tail_dr := tap;
    return v_config;
  end function;

  function jtag_chain
    (nb_user    : natural
    ;supervisor : boolean
    ;inject     : boolean
    ) return t_jtag_chain is
    variable v_chain : t_jtag_chain := (nb_tap => 0, user => -1, nb_user => nb_user, supervisor => -1, inject => -1);
  begin
    -- Chain order from TDI : user CPUs (cluster 0 first), supervisor CPU,
    -- injection
    if nb_user > 0
    then
      v_chain.user       := v_chain.nb_tap;
      v_chain.nb_tap     := v_chain.nb_tap + nb_user;
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
    if    cfg.jtag.nb_user > 0 and tap >= cfg.jtag.user and tap < cfg.jtag.user + cfg.jtag.nb_user
    then
      return std_logic_vector(unsigned(PICOSOC_JTAG_IDCODE_USER_CPU) + to_unsigned((tap - cfg.jtag.user) * 16#10000#, 32));
    elsif tap = cfg.jtag.supervisor
    then
      return PICOSOC_JTAG_IDCODE_SUPERVISOR_CPU;
    elsif tap = cfg.jtag.inject
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

  -----------------------------------------------------------------------------
  -- RISC-V DTM
  -----------------------------------------------------------------------------
  constant C_DMI_IDLE    : natural := 5;  -- Run-Test/Idle cycles after a dmi scan (dtmcs.idle)
  constant DMI_OP_NOP    : std_logic_vector(1 downto 0) := "00";
  constant DMI_OP_READ   : std_logic_vector(1 downto 0) := "01";
  constant DMI_OP_WRITE  : std_logic_vector(1 downto 0) := "10";
  constant DMI_OP_BUSY   : std_logic_vector(1 downto 0) := "11";

  procedure dtmcs_scan
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant data     : in    std_logic_vector(32-1 downto 0)
    ;variable data_out : out   std_logic_vector(32-1 downto 0)
    ;signal   jtag_if  : inout t_jtag_if
    ) is
  begin
    jtag_write_ir(ir_value => JTAG_IR_DTMCS, msg => "dtmcs", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, tap));
    jtag_scan_dr (data_value => data, data_out => data_out, msg => "dtmcs", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, tap));
  end procedure;

  -- Request, then nop scans until the result is not busy ; busy : dmireset,
  -- one more idle cycle, scan again
  procedure dmi_access
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant op       : in    std_logic_vector(1 downto 0)
    ;constant addr     : in    std_logic_vector(DMI_ABITS-1 downto 0)
    ;constant wdata    : in    std_logic_vector(32-1 downto 0)
    ;variable rdata    : out   std_logic_vector(32-1 downto 0)
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    variable v_idle    : natural := C_DMI_IDLE;
    variable v_op      : std_logic_vector(1 downto 0) := op;
    variable v_dmi     : std_logic_vector(DMI_ABITS+32+2-1 downto 0);
    variable v_dtmcs   : std_logic_vector(32-1 downto 0);
  begin
    jtag_write_ir(ir_value => JTAG_IR_DMI, msg => "dmi", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, tap));
    for retry in 1 to 100 loop
      jtag_scan_dr(data_value => addr & wdata & v_op,
                   data_out   => v_dmi,
                   msg        => "dmi",
                   jtag_if    => jtag_if,
                   scope      => C_TB_SCOPE,
                   config     => jtag_config(cfg, tap));
      jtag_idle(num_cycles => v_idle,
                msg        => "after the dmi scan",
                jtag_if    => jtag_if,
                scope      => C_TB_SCOPE,
                config     => jtag_config(cfg, tap));
      if v_dmi(1 downto 0) = DMI_OP_BUSY
      then
        log(ID_BFM, "DMI busy : dmireset, " & integer'image(v_idle+1) & " idle cycles", C_TB_SCOPE);
        dtmcs_scan(cfg, tap, x"00010000", v_dtmcs, jtag_if);
        jtag_write_ir(ir_value => JTAG_IR_DMI, msg => "dmi", jtag_if => jtag_if, scope => C_TB_SCOPE, config => jtag_config(cfg, tap));
        v_idle := v_idle + 1;
      elsif v_op = DMI_OP_NOP
      then
        rdata := v_dmi(33 downto 2);
        return;
      else
        -- Request accepted, the next scan returns its result
        v_op  := DMI_OP_NOP;
      end if;
    end loop;
    alert(ERROR, "DMI access : always busy", C_TB_SCOPE);
  end procedure;

  procedure dmi_write
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant addr     : in    std_logic_vector(DMI_ABITS-1 downto 0)
    ;constant data     : in    std_logic_vector(32-1 downto 0)
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    variable v_rdata   : std_logic_vector(32-1 downto 0);
  begin
    log(ID_BFM, "DMI write 0x" & to_hstring(addr) & " = 0x" & to_hstring(data), C_TB_SCOPE);
    dmi_access(cfg, tap, DMI_OP_WRITE, addr, data, v_rdata, jtag_if);
  end procedure;

  procedure dmi_read
    (constant cfg      : in    t_tb_cfg
    ;constant tap      : in    natural
    ;constant addr     : in    std_logic_vector(DMI_ABITS-1 downto 0)
    ;variable data     : out   std_logic_vector(32-1 downto 0)
    ;signal   jtag_if  : inout t_jtag_if
    ) is
    variable v_rdata   : std_logic_vector(32-1 downto 0);
  begin
    dmi_access(cfg, tap, DMI_OP_READ, addr, x"00000000", v_rdata, jtag_if);
    log(ID_BFM, "DMI read  0x" & to_hstring(addr) & " = 0x" & to_hstring(v_rdata), C_TB_SCOPE);
    data := v_rdata;
  end procedure;

end package body tb_PicoSoC_jtag_pkg;
