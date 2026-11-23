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
use     asylum.techmap_pkg.all;

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
  -- CPU Enable
  constant CPU1_ENABLE                : boolean  := ((SAFETY = "lock-step") or (SAFETY = "tmr"));
  constant CPU2_ENABLE                : boolean  := ((SAFETY = "tmr"));

  -- Lock Step Depth configuration
  constant LOCK_STEP_DEPTH_INT        : natural  := mux2(SAFETY = "lock-step", LOCK_STEP_DEPTH, 0);

  -- Difference vector
  constant DIFF_CPU0_VS_CPU1          : natural  := PICOSOC_SUPERVISOR_GIC_CPU0_VS_CPU1;
  constant DIFF_CPU1_VS_CPU2          : natural  := PICOSOC_SUPERVISOR_GIC_CPU1_VS_CPU2;
  constant DIFF_CPU2_VS_CPU0          : natural  := PICOSOC_SUPERVISOR_GIC_CPU2_VS_CPU0;

  -- SEU bit positions (model-dependent : target the opcode)
  constant CPU0_SEU_BIT               : natural  := mux2(CPU_MODEL = "OpenBlaze8", 17, 
                                                    mux2(CPU_MODEL = "WardRV_fsm",  0, 
                                                         0));
  constant CPU1_SEU_BIT               : natural  := mux2(CPU_MODEL = "OpenBlaze8", 16, 
                                                    mux2(CPU_MODEL = "WardRV_fsm",  1, 
                                                         1));
  constant CPU2_SEU_BIT               : natural  := mux2(CPU_MODEL = "OpenBlaze8", 15,
                                                    mux2(CPU_MODEL = "WardRV_fsm",  2,
                                                         2));
  -- JTAG of the CPU copies
  type jtag_inis_t is array (natural range <>) of jtag_ini_t;
  type jtag_tgts_t is array (natural range <>) of jtag_tgt_t;

  signal jtag_tck                     : std_logic;  -- TCK resynchronized on clk_i (DEBUG_ENABLE)

  -- CPU 0 signals
  signal cpu0_arst_b                  : sls_t     (LOCK_STEP_DEPTH_INT downto 0);
  signal cpu0_ics                     : sls_t     (LOCK_STEP_DEPTH_INT downto 0);
  signal cpu0_iaddr                   : slvs_t    (LOCK_STEP_DEPTH_INT downto 0)(IMEM_ADDR_WIDTH-1 downto 0);
  signal cpu0_idata                   : slvs_t    (LOCK_STEP_DEPTH_INT downto 0)(IMEM_DATA_WIDTH-1 downto 0);
  signal cpu0_sbi_ini                 : sbi_inis_t(LOCK_STEP_DEPTH_INT downto 0)(addr (DMEM_ADDR_WIDTH-1 downto 0),
                                                                                 wdata(DMEM_DATA_WIDTH-1 downto 0));
  signal cpu0_sbi_tgt                 : sbi_tgts_t(LOCK_STEP_DEPTH_INT downto 0)(rdata(DMEM_DATA_WIDTH-1 downto 0));
  signal cpu0_it_val                  : sls_t     (LOCK_STEP_DEPTH_INT downto 0);
  signal cpu0_it_ack                  : sls_t     (LOCK_STEP_DEPTH_INT downto 0);
  signal cpu0_dbg_arst_b              : sls_t     (LOCK_STEP_DEPTH_INT downto 0);
  signal cpu0_jtag_ini                : jtag_inis_t(LOCK_STEP_DEPTH_INT downto 0);
  signal cpu0_jtag_tgt                : jtag_tgts_t(LOCK_STEP_DEPTH_INT downto 0);
  signal cpu0_ndmreset                : sls_t     (LOCK_STEP_DEPTH_INT downto 0);

  -- CPU 1 signals
  signal cpu1_arst_b                  : std_logic;
  signal cpu1_ics                     : std_logic;
  signal cpu1_iaddr                   : std_logic_vector(IMEM_ADDR_WIDTH-1 downto 0);
  signal cpu1_idata                   : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);
  signal cpu1_sbi_ini                 : sbi_ini_t(addr (DMEM_ADDR_WIDTH-1 downto 0),
                                                  wdata(DMEM_DATA_WIDTH-1 downto 0));
  signal cpu1_sbi_tgt                 : sbi_tgt_t(rdata(DMEM_DATA_WIDTH-1 downto 0));
  signal cpu1_it_val                  : std_logic;
  signal cpu1_it_ack                  : std_logic;
  signal cpu1_jtag_tgt                : jtag_tgt_t;
  signal cpu1_ndmreset                : std_logic;
  
  -- CPU 2 signals
  signal cpu2_arst_b                  : std_logic;
  signal cpu2_ics                     : std_logic;
  signal cpu2_iaddr                   : std_logic_vector(IMEM_ADDR_WIDTH-1 downto 0);
  signal cpu2_idata                   : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);
  signal cpu2_sbi_ini                 : sbi_ini_t(addr (DMEM_ADDR_WIDTH-1 downto 0),
                                                  wdata(DMEM_DATA_WIDTH-1 downto 0));
  signal cpu2_sbi_tgt                 : sbi_tgt_t(rdata(DMEM_DATA_WIDTH-1 downto 0));
  signal cpu2_it_val                  : std_logic;
  signal cpu2_it_ack                  : std_logic;
  signal cpu2_jtag_tgt                : jtag_tgt_t;
  signal cpu2_ndmreset                : std_logic;

  -- Error injection and comparison signals
  signal cpu0_idata_with_seu          : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);
  signal cpu1_idata_with_seu          : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);
  signal cpu2_idata_with_seu          : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);
  signal cpu0_idata_seu               : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);
  signal cpu1_idata_seu               : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);
  signal cpu2_idata_seu               : std_logic_vector(IMEM_DATA_WIDTH-1 downto 0);

  signal diff                         : std_logic_vector(3-1 downto 0); -- Instantaneous      difference signals
  signal diff_r                       : std_logic_vector(3-1 downto 0); -- Registered/Latched difference signals
begin

  -----------------------------------------------------------------------------
  -- CPU 0
  -- This is the primary CPU core used in all configurations
  -----------------------------------------------------------------------------
  ins_cpu_0 : entity asylum.cpu_wrapper
    generic map
    (CPU_MODEL       => CPU_MODEL
    ,HARTID          => HARTID
    ,DEBUG_ENABLE    => DEBUG_ENABLE
    ,IDCODE_VALUE    => IDCODE_VALUE
    )
    port map
    (clk_i           => clk_i
    ,cke_i           => cke_i
    ,arst_b_i        => cpu0_arst_b (0)
    ,ics_o           => cpu0_ics    (0)
    ,iaddr_o         => cpu0_iaddr  (0)
    ,idata_i         => cpu0_idata_with_seu
    ,sbi_ini_o       => cpu0_sbi_ini(0)
    ,sbi_tgt_i       => cpu0_sbi_tgt(0)
    ,interrupt_i     => cpu0_it_val (0)
    ,interrupt_ack_o => cpu0_it_ack (0)
    ,dbg_arst_b_i    => cpu0_dbg_arst_b(0)
    ,jtag_ini_i      => cpu0_jtag_ini  (0)
    ,jtag_tgt_o      => cpu0_jtag_tgt  (0)
    ,ndmreset_o      => cpu0_ndmreset  (0)
    );

  cpu0_arst_b    (0) <= arst_b_i;
  cpu0_idata     (0) <= idata_i;
  cpu0_sbi_tgt   (0) <= sbi_tgt_i;
  cpu0_it_val    (0) <= interrupt_i;
  cpu0_dbg_arst_b(0) <= dbg_arst_b_i;
  cpu0_jtag_ini  (0) <= (tck    => jtag_tck
                        ,trst_n => jtag_ini_i.trst_n
                        ,tms    => jtag_ini_i.tms
                        ,tdi    => jtag_ini_i.tdi);

  -- TCK of the debug units resynchronized on clk_i : every copy gets the same
  -- synchronous TCK (CPU1 exactly LOCK_STEP_DEPTH cycles later), so their
  -- debug units stay equal. TMS and TDI are stable around the edges of TCK.
  -- TCK must stay below about clk_i / 8
  gen_jtag_tck_sync: if DEBUG_ENABLE
  generate
    ins_jtag_tck_sync : sync2dffrn
      port map
      (clk_i           => clk_i
      ,arst_b_i        => dbg_arst_b_i
      ,d_i             => jtag_ini_i.tck
      ,q_o             => jtag_tck
      );
  else generate
    jtag_tck <= jtag_ini_i.tck;
  end generate;

  -- Delay pipe for Lock-step
  gen_cpu0_lockstep_pipe: for i in 1 to LOCK_STEP_DEPTH_INT 
  generate
    process (clk_i, arst_b_i) begin
      if arst_b_i = '0' then 
        cpu0_arst_b(i) <= '0';
      elsif rising_edge(clk_i) then
        cpu0_arst_b (i) <= cpu0_arst_b (i-1);
        cpu0_ics    (i) <= cpu0_ics    (i-1);
        cpu0_iaddr  (i) <= cpu0_iaddr  (i-1);
        cpu0_idata  (i) <= cpu0_idata  (i-1);
        cpu0_sbi_ini(i) <= cpu0_sbi_ini(i-1);
        cpu0_sbi_tgt(i) <= cpu0_sbi_tgt(i-1);
        cpu0_it_val (i) <= cpu0_it_val (i-1);
        cpu0_it_ack (i) <= cpu0_it_ack (i-1);
      end if;
    end process;

    -- The debug units run during the CPU reset (ndmreset) : own reset
    process (clk_i, dbg_arst_b_i) begin
      if dbg_arst_b_i = '0' then
        cpu0_dbg_arst_b(i) <= '0';
      elsif rising_edge(clk_i) then
        cpu0_dbg_arst_b(i) <= cpu0_dbg_arst_b(i-1);
        cpu0_jtag_ini  (i) <= cpu0_jtag_ini  (i-1);
        cpu0_jtag_tgt  (i) <= cpu0_jtag_tgt  (i-1);
        cpu0_ndmreset  (i) <= cpu0_ndmreset  (i-1);
      end if;
    end process;
  end generate;

  -----------------------------------------------------------------------------
  -- CPU 1
  -- diff cpu0 vs cpu1
  -----------------------------------------------------------------------------
   gen_cpu1_enable: if CPU1_ENABLE
   generate
    ins_cpu_1 : entity asylum.cpu_wrapper
      generic map
      (CPU_MODEL       => CPU_MODEL
      ,HARTID          => HARTID
      ,DEBUG_ENABLE    => DEBUG_ENABLE
      ,IDCODE_VALUE    => IDCODE_VALUE
      )
      port map
      (clk_i           => clk_i
      ,cke_i           => cke_i
      ,arst_b_i        => cpu1_arst_b
      ,ics_o           => cpu1_ics
      ,iaddr_o         => cpu1_iaddr
      ,idata_i         => cpu1_idata_with_seu
      ,sbi_ini_o       => cpu1_sbi_ini
      ,sbi_tgt_i       => cpu1_sbi_tgt
      ,interrupt_i     => cpu1_it_val
      ,interrupt_ack_o => cpu1_it_ack
      ,dbg_arst_b_i    => cpu0_dbg_arst_b(LOCK_STEP_DEPTH_INT)
      ,jtag_ini_i      => cpu0_jtag_ini  (LOCK_STEP_DEPTH_INT)
      ,jtag_tgt_o      => cpu1_jtag_tgt
      ,ndmreset_o      => cpu1_ndmreset
      );

    cpu1_arst_b  <= cpu0_arst_b  (LOCK_STEP_DEPTH_INT);
    cpu1_idata   <= cpu0_idata   (LOCK_STEP_DEPTH_INT);
    cpu1_sbi_tgt <= cpu0_sbi_tgt (LOCK_STEP_DEPTH_INT);
    cpu1_it_val  <= cpu0_it_val  (LOCK_STEP_DEPTH_INT);
    
    diff(DIFF_CPU0_VS_CPU1) <= '1' when (   (cpu0_ics     (LOCK_STEP_DEPTH_INT) /= cpu1_ics    )
                                         or (cpu0_iaddr   (LOCK_STEP_DEPTH_INT) /= cpu1_iaddr  )
                                         or (cpu0_it_ack  (LOCK_STEP_DEPTH_INT) /= cpu1_it_ack )
                                         or (cpu0_sbi_ini (LOCK_STEP_DEPTH_INT) /= cpu1_sbi_ini)
                                         or (cpu0_jtag_tgt(LOCK_STEP_DEPTH_INT) /= cpu1_jtag_tgt)
                                         or (cpu0_ndmreset(LOCK_STEP_DEPTH_INT) /= cpu1_ndmreset)
                                            ) else
                               '0';
    
    p_diff_r: process (clk_i, cpu1_arst_b) is
    begin  -- process p_diff_r
      if cpu1_arst_b = '0' then                 -- asynchronous reset (active low)
        diff_r(DIFF_CPU0_VS_CPU1) <= '0';
      elsif rising_edge(clk_i) then  -- rising clock edge
        -- Trap 1
        diff_r(DIFF_CPU0_VS_CPU1) <= diff_r(DIFF_CPU0_VS_CPU1) or diff(DIFF_CPU0_VS_CPU1);
      end if;
    end process p_diff_r;
  end generate;

  gen_cpu1_disable: if CPU1_ENABLE = false
  generate
    diff_r(DIFF_CPU0_VS_CPU1) <= '0';
  end generate;

  -----------------------------------------------------------------------------
  -- CPU 2
  -- diff cpu1 vs cpu2
  -- diff cpu2 vs cpu0
  -----------------------------------------------------------------------------
  gen_cpu2_enable: if CPU2_ENABLE 
  generate
    ins_cpu_2 : entity asylum.cpu_wrapper
      generic map
      (CPU_MODEL       => CPU_MODEL
      ,HARTID          => HARTID
      ,DEBUG_ENABLE    => DEBUG_ENABLE
      ,IDCODE_VALUE    => IDCODE_VALUE
      )
      port map
      (clk_i           => clk_i
      ,cke_i           => cke_i
      ,arst_b_i        => cpu2_arst_b
      ,ics_o           => cpu2_ics
      ,iaddr_o         => cpu2_iaddr
      ,idata_i         => cpu2_idata_with_seu
      ,sbi_ini_o       => cpu2_sbi_ini
      ,sbi_tgt_i       => cpu2_sbi_tgt
      ,interrupt_i     => cpu2_it_val
      ,interrupt_ack_o => cpu2_it_ack
      ,dbg_arst_b_i    => cpu0_dbg_arst_b(0)
      ,jtag_ini_i      => cpu0_jtag_ini  (0)
      ,jtag_tgt_o      => cpu2_jtag_tgt
      ,ndmreset_o      => cpu2_ndmreset
      );

    cpu2_arst_b    <= arst_b_i;
    cpu2_idata     <= idata_i;
    cpu2_sbi_tgt   <= sbi_tgt_i;
    cpu2_it_val    <= interrupt_i;   

    diff(DIFF_CPU1_VS_CPU2) <= '1' when (   (cpu1_ics     /= cpu2_ics          )
                                         or (cpu1_iaddr   /= cpu2_iaddr        )
                                         or (cpu1_it_ack  /= cpu2_it_ack       )
                                         or (cpu1_sbi_ini /= cpu2_sbi_ini      )
                                         or (cpu1_jtag_tgt /= cpu2_jtag_tgt    )
                                         or (cpu1_ndmreset /= cpu2_ndmreset    )
                                         ) else
                               '0';
      
    diff(DIFF_CPU2_VS_CPU0) <= '1' when (   (cpu2_ics     /= cpu0_ics     (0)  )
                                         or (cpu2_iaddr   /= cpu0_iaddr   (0)  )
                                         or (cpu2_it_ack  /= cpu0_it_ack  (0)  )
                                         or (cpu2_sbi_ini /= cpu0_sbi_ini (0)  )
                                         or (cpu2_jtag_tgt /= cpu0_jtag_tgt(0) )
                                         or (cpu2_ndmreset /= cpu0_ndmreset(0) )
                                        ) else
                               '0';
    
    p_diff_r: process (clk_i, arst_b_i) is
    begin  -- process p_diff_r
      if arst_b_i= '0' then                 -- asynchronous reset (active low)
        diff_r(DIFF_CPU1_VS_CPU2) <= '0';
        diff_r(DIFF_CPU2_VS_CPU0) <= '0';
      elsif rising_edge(clk_i) then  -- rising clock edge

        -- Trap 1
        diff_r(DIFF_CPU1_VS_CPU2) <= diff_r(DIFF_CPU1_VS_CPU2) or diff(DIFF_CPU1_VS_CPU2);
        diff_r(DIFF_CPU2_VS_CPU0) <= diff_r(DIFF_CPU2_VS_CPU0) or diff(DIFF_CPU2_VS_CPU0);
      end if;
    end process p_diff_r;
  end generate;

  gen_cpu2_disable: if CPU2_ENABLE = false
  generate
    diff_r(DIFF_CPU1_VS_CPU2) <= '0';
    diff_r(DIFF_CPU2_VS_CPU0) <= '0';
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
   gen_cpu_vote: if SAFETY = "tmr" generate
    ics_o          <= ((cpu0_ics     (0) and cpu1_ics       ) or
                       (cpu1_ics         and cpu2_ics       ) or
                       (cpu2_ics         and cpu0_ics    (0)));
    iaddr_o        <= ((cpu0_iaddr   (0) and cpu1_iaddr     ) or
                       (cpu1_iaddr       and cpu2_iaddr     ) or
                       (cpu2_iaddr       and cpu0_iaddr  (0)));
    sbi_ini_o      <= vote(cpu0_sbi_ini(0), cpu1_sbi_ini, cpu2_sbi_ini); -- sbi_pkg
    interrupt_ack_o<= ((cpu0_it_ack  (0) and cpu1_it_ack    ) or
                       (cpu1_it_ack      and cpu2_it_ack    ) or
                       (cpu2_it_ack      and cpu0_it_ack (0)));
    -- No operator on jtag_tgt_t : voted field by field
    jtag_tgt_o.tdo    <= ((cpu0_jtag_tgt(0).tdo    and cpu1_jtag_tgt.tdo   ) or
                          (cpu1_jtag_tgt.tdo       and cpu2_jtag_tgt.tdo   ) or
                          (cpu2_jtag_tgt.tdo       and cpu0_jtag_tgt(0).tdo));
    jtag_tgt_o.tdo_en <= ((cpu0_jtag_tgt(0).tdo_en and cpu1_jtag_tgt.tdo_en) or
                          (cpu1_jtag_tgt.tdo_en    and cpu2_jtag_tgt.tdo_en) or
                          (cpu2_jtag_tgt.tdo_en    and cpu0_jtag_tgt(0).tdo_en));
    ndmreset_o        <= ((cpu0_ndmreset(0)        and cpu1_ndmreset       ) or
                          (cpu1_ndmreset           and cpu2_ndmreset       ) or
                          (cpu2_ndmreset           and cpu0_ndmreset(0)    ));
 
  else generate
    ics_o           <= cpu0_ics    (0);
    iaddr_o         <= cpu0_iaddr  (0);
    sbi_ini_o       <= cpu0_sbi_ini(0);
    interrupt_ack_o <= cpu0_it_ack (0);
    jtag_tgt_o      <= cpu0_jtag_tgt(0);
    ndmreset_o      <= cpu0_ndmreset(0);
  end generate;

  -----------------------------------------------------------------------------
  -- Fault Injection
  -----------------------------------------------------------------------------
  gen_inject_error: if FAULT_INJECTION
  generate
    process(inject_error_i) is
    begin
      cpu0_idata_seu               <= (others => '0');
      cpu1_idata_seu               <= (others => '0');
      cpu2_idata_seu               <= (others => '0');
      cpu0_idata_seu(CPU0_SEU_BIT) <= inject_error_i(0);
      cpu1_idata_seu(CPU1_SEU_BIT) <= inject_error_i(1);
      cpu2_idata_seu(CPU2_SEU_BIT) <= inject_error_i(2);
    end process;
  else generate
    cpu0_idata_seu                 <= (others => '0');
    cpu1_idata_seu                 <= (others => '0');
    cpu2_idata_seu                 <= (others => '0');
  end generate;

  cpu0_idata_with_seu <= cpu0_idata(0) xor cpu0_idata_seu;
  cpu1_idata_with_seu <= cpu1_idata    xor cpu1_idata_seu;
  cpu2_idata_with_seu <= cpu2_idata    xor cpu2_idata_seu;

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
  process(diff_r(DIFF_CPU0_VS_CPU1))
  begin
    if true --(diff_r(DIFF_CPU0_VS_CPU1) /= '0')
    then
      report "CPU Safety: Difference (CPU0 VS CPU1) : " & std_logic'image(diff_r(DIFF_CPU0_VS_CPU1))
      severity warning;
    end if;
  end process;

  process(diff_r(DIFF_CPU1_VS_CPU2))
  begin
    if true --(diff_r(DIFF_CPU1_VS_CPU2) /= '0')
    then
      report "CPU Safety: Difference (CPU1 VS CPU2) : " & std_logic'image(diff_r(DIFF_CPU1_VS_CPU2))
      severity warning;
    end if;
  end process;

  process(diff_r(DIFF_CPU2_VS_CPU0))
  begin
    if true --(diff_r(DIFF_CPU2_VS_CPU0) /= '0')
    then
      report "CPU Safety: Difference (CPU2 VS CPU0) : " & std_logic'image(diff_r(DIFF_CPU2_VS_CPU0))
      severity warning;
    end if;
  end process;

  -- pragma translate_on

end architecture;
