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
    (SAFETY                : string   := "lock-step"
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
  -- Number of copies of the CPU, compared pairs (copy i with copy i+1 mod 3) :
  -- none, 0-1 (lock-step), 0-1 1-2 2-0 (TMR)
  constant NB_CPU                     : positive := mux2(SAFETY = "tmr", 3, mux2(SAFETY = "lock-step", 2, 1));
  constant NB_DIFF                    : natural  := mux2(NB_CPU = 3, 3, NB_CPU-1);

  -- Lock Step Depth configuration
  constant LOCK_STEP_DEPTH_INT        : natural  := mux2(SAFETY = "lock-step", LOCK_STEP_DEPTH, 0);

  type     naturals_t                 is array (natural range <>) of natural;

  -- Difference vector : bit of the pair (copy i, copy i+1 mod 3)
  constant DIFF_BIT                   : naturals_t(0 to 3-1) := (PICOSOC_SUPERVISOR_GIC_CPU0_VS_CPU1
                                                                ,PICOSOC_SUPERVISOR_GIC_CPU1_VS_CPU2
                                                                ,PICOSOC_SUPERVISOR_GIC_CPU2_VS_CPU0);

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

  -- Stage of the lock-step pipe of the inputs of each copy : CPU0 gets the
  -- inputs, the other copies LOCK_STEP_DEPTH cycles later (TMR : depth 0)
  constant STAGE                      : naturals_t(0 to 3-1) := (0, LOCK_STEP_DEPTH_INT, LOCK_STEP_DEPTH_INT);

  -- Inputs of a copy : CPU reset domain (arst_b), debug unit reset domain
  -- (dbg_arst_b)
  type     cpu_in_t                   is record
    arst_b                            : std_logic;
    idata                             : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);
    sbi_tgt                           : sbi_tgt_t(rdata(DMEM_DATA_WIDTH-1 downto 0));
    it_val                            : std_logic;
    dbg_arst_b                        : std_logic;
    jtag_ini                          : jtag_ini_t;
  end record cpu_in_t;

  -- Outputs of a copy : compared (lock-step, TMR) and voted (TMR)
  type     cpu_out_t                  is record
    ics                               : std_logic;
    iaddr                             : std_logic_vector(IMEM_ADDR_WIDTH-1 downto 0);
    it_ack                            : std_logic;
    sbi_ini                           : sbi_ini_t(addr (DMEM_ADDR_WIDTH-1 downto 0),
                                                  wdata(DMEM_DATA_WIDTH-1 downto 0));
    jtag_tgt                          : jtag_tgt_t;
    ndmreset                          : std_logic;
  end record cpu_out_t;

  type     cpu_ins_t                  is array (natural range <>) of cpu_in_t;
  type     cpu_outs_t                 is array (natural range <>) of cpu_out_t;

  -- Two copies differ : the "/=" of sbi_pkg for the data bus request (addr
  -- when cs = '1', wdata when we = '1'), every other field compared
  function "/=" (a, b : cpu_out_t) return boolean is
  begin
    return (a.ics      /= b.ics     ) or
           (a.iaddr    /= b.iaddr   ) or
           (a.it_ack   /= b.it_ack  ) or
           (a.sbi_ini  /= b.sbi_ini ) or
           (a.jtag_tgt /= b.jtag_tgt) or
           (a.ndmreset /= b.ndmreset);
  end function "/=";

  -- Majority of three bits / vectors (no vote of std_logic in the packages)
  function vote (a, b, c : std_logic) return std_logic is
  begin
    return (a and b) or (b and c) or (c and a);
  end function vote;

  function vote (a, b, c : std_logic_vector) return std_logic_vector is
  begin
    return (a and b) or (b and c) or (c and a);
  end function vote;

  -- TMR vote of the outputs of the three copies : vote of sbi_pkg for the
  -- data bus request, a majority for every other field
  function vote (a, b, c : cpu_out_t) return cpu_out_t is
    variable z : cpu_out_t;
  begin
    z.ics             := vote(a.ics            , b.ics            , c.ics            );
    z.iaddr           := vote(a.iaddr          , b.iaddr          , c.iaddr          );
    z.it_ack          := vote(a.it_ack         , b.it_ack         , c.it_ack         );
    z.sbi_ini         := vote(a.sbi_ini        , b.sbi_ini        , c.sbi_ini        ); -- sbi_pkg
    z.jtag_tgt.tdo    := vote(a.jtag_tgt.tdo   , b.jtag_tgt.tdo   , c.jtag_tgt.tdo   );
    z.jtag_tgt.tdo_en := vote(a.jtag_tgt.tdo_en, b.jtag_tgt.tdo_en, c.jtag_tgt.tdo_en);
    z.ndmreset        := vote(a.ndmreset       , b.ndmreset       , c.ndmreset       );
    return z;
  end function vote;

  -- Lock-step pipe : stage 0 = the inputs of cpu_safety and the outputs of
  -- CPU0, stage i = stage 0 delayed by i cycles. The other copies get the
  -- inputs of the last stage, their outputs are compared with the outputs
  -- of CPU0 of the last stage (TMR : depth 0, no delay)
  signal   pipe_in                    : cpu_ins_t (0 to LOCK_STEP_DEPTH_INT);
  signal   pipe_out                   : cpu_outs_t(0 to LOCK_STEP_DEPTH_INT);

  -- Outputs of the copies (copy 0 : CPU0 of the last stage of the pipe)
  signal   cpu_out                    : cpu_outs_t(0 to 3-1);
  signal   cpu_voted                  : cpu_out_t;

  signal   diff                       : std_logic_vector(3-1 downto 0); -- Instantaneous      difference signals
  signal   diff_r                     : std_logic_vector(3-1 downto 0); -- Registered/Latched difference signals
begin

  -----------------------------------------------------------------------------
  -- Inputs : stage 0 of the lock-step pipe
  -----------------------------------------------------------------------------
  pipe_in(0) <= (arst_b     => arst_b_i
                ,idata      => idata_i
                ,sbi_tgt    => sbi_tgt_i
                ,it_val     => interrupt_i
                ,dbg_arst_b => dbg_arst_b_i
                ,jtag_ini   => jtag_ini_i);

  -- TCK of the debug units : already resynchronized on clk_i by PicoSoC_top,
  -- so every copy gets the same synchronous TCK (CPU1 exactly LOCK_STEP_DEPTH
  -- cycles later) and their debug units stay equal. TMS and TDI are stable
  -- around the edges of TCK. TCK must stay below about clk_i / 8

  -----------------------------------------------------------------------------
  -- Delay pipe for Lock-step
  -----------------------------------------------------------------------------
  gen_lockstep_pipe: for i in 1 to LOCK_STEP_DEPTH_INT
  generate
    process (clk_i, arst_b_i) begin
      if arst_b_i = '0' then
        pipe_in (i).arst_b     <= '0';
      elsif rising_edge(clk_i) then
        pipe_in (i).arst_b     <= pipe_in (i-1).arst_b;
        pipe_in (i).idata      <= pipe_in (i-1).idata;
        pipe_in (i).sbi_tgt    <= pipe_in (i-1).sbi_tgt;
        pipe_in (i).it_val     <= pipe_in (i-1).it_val;
        pipe_out(i).ics        <= pipe_out(i-1).ics;
        pipe_out(i).iaddr      <= pipe_out(i-1).iaddr;
        pipe_out(i).it_ack     <= pipe_out(i-1).it_ack;
        pipe_out(i).sbi_ini    <= pipe_out(i-1).sbi_ini;
      end if;
    end process;

    -- The debug units run during the CPU reset (ndmreset) : own reset
    process (clk_i, dbg_arst_b_i) begin
      if dbg_arst_b_i = '0' then
        pipe_in (i).dbg_arst_b <= '0';
      elsif rising_edge(clk_i) then
        pipe_in (i).dbg_arst_b <= pipe_in (i-1).dbg_arst_b;
        pipe_in (i).jtag_ini   <= pipe_in (i-1).jtag_ini;
        pipe_out(i).jtag_tgt   <= pipe_out(i-1).jtag_tgt;
        pipe_out(i).ndmreset   <= pipe_out(i-1).ndmreset;
      end if;
    end process;
  end generate;

  -----------------------------------------------------------------------------
  -- CPU copies
  -- CPU0 : the primary CPU, used in all configurations
  -- CPU1 : lock-step and TMR ; CPU2 : TMR
  -----------------------------------------------------------------------------
  gen_cpu: for i in 0 to NB_CPU-1
  generate
    signal   cpu_in    : cpu_in_t;  -- Inputs of the copy
    signal   idata     : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);
    signal   inject    : std_logic_vector(4-1 downto 0);  -- Injection inside the CPU of the copy
    signal   out_cpu   : cpu_out_t;
  begin
    -- A signal assignment, not a direct read of the pipe registers : the
    -- inputs change a delta cycle after them, OpenBlaze8 samples them on its
    -- internal clock (a delta cycle after clk_i) at the next edge only
    cpu_in <= pipe_in(STAGE(i));

    -- Fault Injection : one instruction bit of the copy flipped
    process (cpu_in, inject_error_i) is
    begin
      idata                <= cpu_in.idata;
      if FAULT_INJECTION
      then
        idata(SEU_BIT(i))  <= cpu_in.idata(SEU_BIT(i)) xor inject_error_i(i);
      end if;
    end process;

    -- Fault Injection inside the CPU (a hardened CPU uses it, not the
    -- reference ones)
    inject <= inject_cpu_i(4*i+3 downto 4*i) when FAULT_INJECTION else
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
      ,arst_b_i        => cpu_in.arst_b
      ,ics_o           => out_cpu.ics
      ,iaddr_o         => out_cpu.iaddr
      ,idata_i         => idata
      ,sbi_ini_o       => out_cpu.sbi_ini
      ,sbi_tgt_i       => cpu_in.sbi_tgt
      ,interrupt_i     => cpu_in.it_val
      ,interrupt_ack_o => out_cpu.it_ack
      ,inject_i        => inject
      ,dbg_arst_b_i    => cpu_in.dbg_arst_b
      ,jtag_ini_i      => cpu_in.jtag_ini
      ,jtag_tgt_o      => out_cpu.jtag_tgt
      ,ndmreset_o      => out_cpu.ndmreset
      );

    -- CPU0 : through the pipe, aligned with the other copies
    gen_cpu0: if i = 0
    generate
      pipe_out(0) <= out_cpu;
      cpu_out (i) <= pipe_out(LOCK_STEP_DEPTH_INT);
    else generate
      cpu_out (i) <= out_cpu;
    end generate;
  end generate;

  -----------------------------------------------------------------------------
  -- Differences : copy i vs copy i+1 mod 3, trapped until the reset of the
  -- copy i+1 mod 3
  -----------------------------------------------------------------------------
  gen_diff: for i in 0 to 3-1
  generate
    constant NEXT_CPU  : natural := (i+1) mod 3;
    -- Reset of the copy i+1 mod 3 (an alias : GHDL 6.0.0 crashes on a
    -- field of pipe_in in a sensitivity list)
    alias    arst_b    : std_logic is pipe_in(STAGE(NEXT_CPU)).arst_b;
  begin
    gen_compared: if i < NB_DIFF
    generate
      diff(DIFF_BIT(i)) <= '1' when cpu_out(i) /= cpu_out(NEXT_CPU) else
                           '0';

      p_diff_r: process (clk_i, arst_b) is
      begin  -- process p_diff_r
        if arst_b = '0' then -- asynchronous reset (active low)
          diff_r(DIFF_BIT(i)) <= '0';
        elsif rising_edge(clk_i) then  -- rising clock edge
          -- Trap 1
          diff_r(DIFF_BIT(i)) <= diff_r(DIFF_BIT(i)) or diff(DIFF_BIT(i));
        end if;
      end process p_diff_r;
    else generate
      diff_r(DIFF_BIT(i)) <= '0';
    end generate;
  end generate;

  -----------------------------------------------------------------------------
  -- CPU Signals
  --  * ROM interface
  --  * ICN interface
  --  * IT  interface
  --  * JTAG TDO and ndmreset of the debug unit
  --
  -- If safety none or lock-step : take cpu 0
  -- else if tmr : vote all cpu output
  -----------------------------------------------------------------------------
  gen_cpu_vote: if SAFETY = "tmr"
  generate
    cpu_voted <= vote(cpu_out(0), cpu_out(1), cpu_out(2));
  else generate
    cpu_voted <= pipe_out(0);
  end generate;

  ics_o           <= cpu_voted.ics;
  iaddr_o         <= cpu_voted.iaddr;
  sbi_ini_o       <= cpu_voted.sbi_ini;
  interrupt_ack_o <= cpu_voted.it_ack;
  jtag_tgt_o      <= cpu_voted.jtag_tgt;
  ndmreset_o      <= cpu_voted.ndmreset;

  -----------------------------------------------------------------------------
  -- Difference vector output
  -----------------------------------------------------------------------------
  diff_o              <= diff_r;

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

  -- Display difference vector upon detection
  gen_report: for i in 0 to 3-1
  generate
    alias    diff_trap : std_logic is diff_r(DIFF_BIT(i));
  begin
    process(diff_trap)
    begin
      report "CPU Safety: Difference (CPU" & integer'image(i) & " VS CPU" & integer'image((i+1) mod 3) & ") : " & std_logic'image(diff_trap)
      severity warning;
    end process;
  end generate;

  -- pragma translate_on

end architecture;
