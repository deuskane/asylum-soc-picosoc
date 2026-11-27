-------------------------------------------------------------------------------
-- Title      : CPU Safety wrapper
-- Project    : 
-------------------------------------------------------------------------------
-- File       : cpu_safety.vhd
-- Author     : Mathieu Rosière
-- Company    : 
-- Created    : 2026-05-20
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This module wraps the CPU with safety logic (Lock-step or TMR).
--              Student branch : only SAFETY = "none" is implemented.
--              "lock-step" and "tmr" are holes to write (gen_lock_step,
--              gen_tmr) : a target that selects them fails on their
--              assertion.
--              Debug units (DEBUG_ENABLE) : jtag_ini_i.tck is already
--              resynchronized on clk_i by PicoSoC_top (one synchronizer for
--              the whole JTAG chain) : it goes to every copy like the other
--              inputs
--              Error injection : inject_error_i(i) flips the instruction bit
--              SEU_BIT(i) of the copy i (outside the CPU) ; inject_cpu_i
--              (4*i+3 downto 4*i) goes to inject_i of the cpu_wrapper of
--              the copy i (inside the CPU : 4 requests, one clock cycle per
--              injection, unused by the reference CPUs, free for a hardened
--              CPU), with FAULT_INJECTION
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-05-20  1.0      mrosiere Created
-- 2026-05-21  1.1      mrosiere Cosmetics
-- 2026-11-19  1.2      mrosiere Compare the data bus requests ("/=" of sbi_pkg :
--                               addr when cs = '1', wdata when we = '1')
-- 2026-11-21  1.3      mrosiere HARTID of the redundant CPUs (the copies of a
--                               hart read the same mhartid as CPU0)
-- 2026-11-23  1.4      mrosiere DEBUG_ENABLE : debug unit in each copy
--                               (cpu_wrapper). JTAG pins, TCK resynchronized,
--                               to every copy like the other inputs ; TDO and
--                               ndmreset compared (lock-step) or voted (TMR)
-- 2026-11-23  1.5      mrosiere TMR : vote of the data bus requests with
--                               vote of sbi_pkg
-- 2026-11-23  1.6      mrosiere Outputs of a copy in a record (cpu_out_t,
--                               its "/=" and vote), inputs in another
--                               (cpu_in_t), lock-step pipe as arrays of
--                               records, one generate over the copies
-- 2026-11-26  1.7      mrosiere Synchronizer of TCK removed : jtag_ini_i.tck
--                               resynchronized once for the whole chain in
--                               PicoSoC_top
-- 2026-11-27  1.8      mrosiere SEU_BIT of WardRV : bits 7 / 8 / 9 (rd field)
--                               in place of 0 / 1 / 2 (opcode low bits)
-- 2026-11-27  1.9      mrosiere inject_cpu_i : injection inside the CPU of
--                               each copy (inject_i of cpu_wrapper)
-- 2026-11-28  1.10     mrosiere inject_cpu_i of 12 bits : 4 requests per copy
-- 2026-11-27  2.2      mrosiere Student branch : lock-step and TMR removed,
--                               holes to write ; SAFETY = "none" by default
-------------------------------------------------------------------------------
library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.sbi_pkg.all;
use     asylum.logic_pkg.all;
use     asylum.math_pkg.all;
use     asylum.PicoSoC_pkg.all;
use     asylum.jtag_pkg.all;

entity cpu_safety is
  generic
    (SAFETY                : string   := "none"      -- "none" / "lock-step" / "tmr" (to write)
    ;LOCK_STEP_DEPTH       : natural  := 2
    ;FAULT_INJECTION       : boolean  := False
    ;CPU_MODEL             : string   := "OpenBlaze8"
    ;HARTID                : std_logic_vector(31 downto 0) := x"00000000"
    ;DEBUG_ENABLE          : boolean  := False -- WardRV_fsm : debug unit in each copy (cpu_wrapper)
    ;IDCODE_VALUE          : std_logic_vector(31 downto 0) := x"10000001" -- IDCODE of its TAP
    ;IMEM_ADDR_WIDTH       : positive := 12
    ;IMEM_DATA_WIDTH       : positive := 18
    ;DMEM_ADDR_WIDTH       : positive := SBI_ADDR_WIDTH
    ;DMEM_DATA_WIDTH       : positive := SBI_DATA_WIDTH
    );
  port
    (clk_i                 : in  std_logic
    ;cke_i                 : in  std_logic
    ;arst_b_i              : in  std_logic

    -- Instruction Interface
    ;ics_o                 : out std_logic
    ;iaddr_o               : out std_logic_vector(IMEM_ADDR_WIDTH-1 downto 0)
    ;idata_i               : in  std_logic_vector(IMEM_DATA_WIDTH-1 downto 0)

    -- Data 
    ;sbi_ini_o             : out sbi_ini_t
    ;sbi_tgt_i             : in  sbi_tgt_t

    -- Interrupts
    ;interrupt_i           : in  std_logic
    ;interrupt_ack_o       : out std_logic

    -- Error injection and difference output
    ;inject_error_i        : in  std_logic_vector(3-1 downto 0)
    ;inject_cpu_i          : in  std_logic_vector(12-1 downto 0) := (others => '0') -- Inside the CPU copy i : bits 4*i+3 downto 4*i (one cycle per injection)
    ;diff_o                : out std_logic_vector(3-1 downto 0)

    -- Debug unit (DEBUG_ENABLE) : JTAG pins, power-on reset of the debug unit,
    -- ndmreset ; without debug unit : TDO = TDI
    ;dbg_arst_b_i          : in  std_logic := '1'
    ;jtag_ini_i            : in  jtag_ini_t
    ;jtag_tgt_o            : out jtag_tgt_t
    ;ndmreset_o            : out std_logic
    );
end cpu_safety;

architecture rtl of cpu_safety is
  type     naturals_t                 is array (natural range <>) of natural;

  -- SEU bit positions of each copy (model-dependent), chosen so that a
  -- flipped bit makes the program go wrong even when nothing detects it :
  -- * OpenBlaze8 : bits 17 / 16 / 15 of the opcode
  -- * WardRV     : bits 7 / 8 / 9, rd(2:0) : the instruction writes another
  --   register (an rd of x0 becomes a real register), or a store / branch
  --   gets another immediate (imm(4:0) of S, imm(11) / imm(2:1) of B) ;
  --   the low bits of the opcode (0 / 1 / 2 before) give an unknown opcode,
  --   that WardRV_fsm runs as a no-operation : the program often goes on
  constant SEU_BIT                    : naturals_t(0 to 3-1) := (mux2(CPU_MODEL = "OpenBlaze8", 17, 7)
                                                                ,mux2(CPU_MODEL = "OpenBlaze8", 16, 8)
                                                                ,mux2(CPU_MODEL = "OpenBlaze8", 15, 9));
begin

  -----------------------------------------------------------------------------
  -- SAFETY = "none" : one CPU, its outputs are the outputs of cpu_safety
  -----------------------------------------------------------------------------
  gen_none: if SAFETY = "none"
  generate
    signal   idata     : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);
    signal   inject    : std_logic_vector(4-1 downto 0);  -- Injection inside the CPU (inject_i of cpu_wrapper)
  begin
    -- Fault Injection : inject_error_i(0) flips one instruction bit of the
    -- CPU. Nothing detects it (no copy to compare with, diff_o stays 0) : the
    -- trap of PicoSoC_inject keeps the error until the power-on reset (or a
    -- 1 -> 0 of the request of the injection / status TAP)
    process (idata_i, inject_error_i) is
    begin
      idata                <= idata_i;
      if FAULT_INJECTION
      then
        idata(SEU_BIT(0))  <= idata_i(SEU_BIT(0)) xor inject_error_i(0);
      end if;
    end process;

    -- Fault Injection inside the CPU : the 4 requests of the copy 0 (a
    -- hardened CPU uses them, not the reference ones)
    inject <= inject_cpu_i(4-1 downto 0) when FAULT_INJECTION else
              "0000";

    ins_cpu : entity asylum.cpu_wrapper
      generic map
      (CPU_MODEL       => CPU_MODEL
      ,HARTID          => HARTID
      ,DEBUG_ENABLE    => DEBUG_ENABLE
      ,IDCODE_VALUE    => IDCODE_VALUE
      )
      port map
      (clk_i           => clk_i
      ,cke_i           => cke_i
      ,arst_b_i        => arst_b_i
      ,ics_o           => ics_o
      ,iaddr_o         => iaddr_o
      ,idata_i         => idata
      ,sbi_ini_o       => sbi_ini_o
      ,sbi_tgt_i       => sbi_tgt_i
      ,interrupt_i     => interrupt_i
      ,interrupt_ack_o => interrupt_ack_o
      ,inject_i        => inject
      ,dbg_arst_b_i    => dbg_arst_b_i
      ,jtag_ini_i      => jtag_ini_i
      ,jtag_tgt_o      => jtag_tgt_o
      ,ndmreset_o      => ndmreset_o
      );

    -- No copy to compare with
    diff_o <= (others => '0');
  end generate gen_none;

  -----------------------------------------------------------------------------
  -- SAFETY = "lock-step" : to write
  --  * Two copies of the CPU (cpu_wrapper, instantiated as in gen_none, with
  --    the same generics : the copies of a hart read the same HARTID).
  --  * CPU0 drives the outputs of cpu_safety. CPU1 runs LOCK_STEP_DEPTH
  --    clock cycles after CPU0 : its inputs (arst_b_i, idata_i, sbi_tgt_i,
  --    interrupt_i, and dbg_arst_b_i, jtag_ini_i for its debug unit) are the
  --    inputs of CPU0 delayed by LOCK_STEP_DEPTH registers.
  --  * The outputs of CPU0, delayed by LOCK_STEP_DEPTH registers too, are
  --    compared with the outputs of CPU1 (ics, iaddr, interrupt_ack,
  --    sbi_ini, jtag_tgt, ndmreset) : a difference sets the bit
  --    PICOSOC_SUPERVISOR_GIC_CPU0_VS_CPU1 (PicoSoC_pkg) of diff_o until
  --    the reset (sticky) ; the other bits of diff_o stay at '0'. The
  --    supervisor (esw/system/supervisor.c) then resets the user SoC.
  --  * FAULT_INJECTION : inject_error_i(i) flips the bit SEU_BIT(i) of the
  --    instruction of the copy i (as in gen_none for CPU0). The request
  --    stays at '1' (trap of PicoSoC_inject) until a difference flag of the
  --    copy i rises in diff_o. Injection inside the CPU : inject_cpu_i
  --    (4*i+3 downto 4*i) to inject_i of the cpu_wrapper of the copy i (as
  --    in gen_none for CPU0, with FAULT_INJECTION).
  --  Available : jtag_ini_i (JTAG pins, TCK already resynchronized on
  --  clk_i), SEU_BIT, the "/=" of sbi_pkg (sbi_ini_t : addr compared when
  --  cs = '1', wdata when we = '1'), your safety_pkg (use
  --  asylum.safety_pkg.all, with its core in the depend list of files_hdl
  --  in PicoSoC.core).
  --  Diagram : doc/picosoc-cpu_safety-lock_step.png
  --  Test : make _sim_soc2_wardrv_fsm_fault_c_user_loop (scenario fault_lock_step)
  -----------------------------------------------------------------------------
  gen_lock_step: if SAFETY = "lock-step"
  generate
    assert false
      report "SAFETY = ""lock-step"" not implemented"
      severity failure;
  end generate gen_lock_step;

  -----------------------------------------------------------------------------
  -- SAFETY = "tmr" : to write
  --  * Three copies of the CPU (cpu_wrapper, as in gen_none), with the same
  --    inputs at the same time (no delay).
  --  * Each output of cpu_safety is the majority of the outputs of the three
  --    copies, bit by bit (ics, iaddr, interrupt_ack, sbi_ini, jtag_tgt,
  --    ndmreset).
  --  * diff_o : copy i compared with copy i+1 mod 3, the bit
  --    PICOSOC_SUPERVISOR_GIC_CPU0_VS_CPU1, _CPU1_VS_CPU2, _CPU2_VS_CPU0
  --    (PicoSoC_pkg) set until the reset (sticky). The supervisor
  --    (esw/system/supervisor.c -DSAFETY_TMR) masks a first error, resets
  --    the user SoC on a second one.
  --  * FAULT_INJECTION : as in lock-step, one bit of inject_error_i per copy,
  --    trapped until a difference flag of the copy rises, and the 4 bits of
  --    inject_cpu_i of each copy to the inject_i of its cpu_wrapper.
  --  Available : as in lock-step, the TMR of your safety_pkg.
  --  Diagram : doc/picosoc-cpu_safety-TMR.png
  --  Test : make _sim_soc3_wardrv_fsm_fault_c_user_loop (scenario fault_tmr)
  -----------------------------------------------------------------------------
  gen_tmr: if SAFETY = "tmr"
  generate
    assert false
      report "SAFETY = ""tmr"" not implemented"
      severity failure;
  end generate gen_tmr;

  -----------------------------------------------------------------------------
  -- Check SAFETY Value
  -----------------------------------------------------------------------------
  assert (SAFETY = "none"      or
          SAFETY = "lock-step" or
          SAFETY = "tmr")
    report "Invalid SAFETY: " & SAFETY
    severity failure;

  -----------------------------------------------------------------------------
  -- Reports
  -----------------------------------------------------------------------------
  -- pragma translate_off
  -- Display configuration at simulation start
  process
  begin
    report "CPU Safety Wrapper Configuration";
    report " * CPU Model : " & CPU_MODEL;
    report " * Safety    : " & SAFETY;
    wait;
  end process;
  -- pragma translate_on

end architecture;
