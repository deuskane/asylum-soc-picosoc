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
-------------------------------------------------------------------------------
library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.sbi_pkg.all;
use     asylum.logic_pkg.all;
use     asylum.math_pkg.all;
use     asylum.PicoSoC_pkg.all;

entity cpu_safety is
  generic
    (SAFETY                : string   := "lock-step"
    ;LOCK_STEP_DEPTH       : natural  := 2
    ;FAULT_INJECTION       : boolean  := False
    ;CPU_MODEL             : string   := "OpenBlaze8"
    ;IMEM_ADDR_WIDTH       : positive := 12
    ;IMEM_DATA_WIDTH       : positive := 18
    );
  port
    (clk_i                 : in  std_logic
    ;cke_i                 : in  std_logic
    ;arst_b_i              : in  std_logic
    ;ics_o                 : out std_logic
    ;iaddr_o               : out std_logic_vector(IMEM_ADDR_WIDTH-1 downto 0)
    ;idata_i               : in  std_logic_vector(IMEM_DATA_WIDTH-1 downto 0)
    ;sbi_ini_o             : out sbi_ini_t
    ;sbi_tgt_i             : in  sbi_tgt_t
    ;interrupt_i           : in  std_logic
    ;interrupt_ack_o       : out std_logic
    ;inject_error_i        : in  std_logic_vector(3-1 downto 0)
    ;diff_o                : out std_logic_vector(3-1 downto 0)
    );
end cpu_safety;

architecture rtl of cpu_safety is
  -- CPU Enable
  constant CPU1_ENABLE                : boolean  := ((SAFETY = "lock-step") or (SAFETY = "tmr"));
  constant CPU2_ENABLE                : boolean  := ((SAFETY = "tmr"));

  -- Data Memory Configuration
  constant DMEM_ADDR_WIDTH            : positive := SBI_ADDR_WIDTH;
  constant DMEM_DATA_WIDTH            : positive := SBI_DATA_WIDTH;

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
    );

  cpu0_arst_b (0) <= arst_b_i;
  cpu0_idata  (0) <= idata_i;
  cpu0_sbi_tgt(0) <= sbi_tgt_i;
  cpu0_it_val (0) <= interrupt_i;

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
      );

    cpu1_arst_b  <= cpu0_arst_b  (LOCK_STEP_DEPTH_INT);
    cpu1_idata   <= cpu0_idata   (LOCK_STEP_DEPTH_INT);
    cpu1_sbi_tgt <= cpu0_sbi_tgt (LOCK_STEP_DEPTH_INT);
    cpu1_it_val  <= cpu0_it_val  (LOCK_STEP_DEPTH_INT);
    
    diff(DIFF_CPU0_VS_CPU1) <= '1' when (   (cpu0_ics     (LOCK_STEP_DEPTH_INT) /= cpu1_ics    )
                                         or (cpu0_iaddr   (LOCK_STEP_DEPTH_INT) /= cpu1_iaddr  )
                                         or (cpu0_it_ack  (LOCK_STEP_DEPTH_INT) /= cpu1_it_ack )
                                       --or (cpu0_sbi_ini (LOCK_STEP_DEPTH_INT) /= cpu1_sbi_ini)
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
      );

    cpu2_arst_b    <= arst_b_i;
    cpu2_idata     <= idata_i;
    cpu2_sbi_tgt   <= sbi_tgt_i;
    cpu2_it_val    <= interrupt_i;   

    diff(DIFF_CPU1_VS_CPU2) <= '1' when (   (cpu1_ics     /= cpu2_ics          )
                                         or (cpu1_iaddr   /= cpu2_iaddr        )
                                         or (cpu1_it_ack  /= cpu2_it_ack       )
                                       --or (cpu1_sbi_ini /= cpu2_sbi_ini      )
                                         ) else
                               '0';
      
    diff(DIFF_CPU2_VS_CPU0) <= '1' when (   (cpu2_ics     /= cpu0_ics     (0)  )
                                         or (cpu2_iaddr   /= cpu0_iaddr   (0)  )
                                         or (cpu2_it_ack  /= cpu0_it_ack  (0)  )
                                       --or (cpu2_sbi_ini /= cpu0_sbi_ini (0)  )
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
    sbi_ini_o      <= ((cpu0_sbi_ini (0) and cpu1_sbi_ini   ) or
                       (cpu1_sbi_ini     and cpu2_sbi_ini   ) or
                       (cpu2_sbi_ini     and cpu0_sbi_ini(0)));
    interrupt_ack_o<= ((cpu0_it_ack  (0) and cpu1_it_ack    ) or
                       (cpu1_it_ack      and cpu2_it_ack    ) or
                       (cpu2_it_ack      and cpu0_it_ack (0)));
 
  else generate
    ics_o           <= cpu0_ics    (0);
    iaddr_o         <= cpu0_iaddr  (0);
    sbi_ini_o       <= cpu0_sbi_ini(0);
    interrupt_ack_o <= cpu0_it_ack (0);
  end generate;

  -----------------------------------------------------------------------------
  -- Fault Injection
  -----------------------------------------------------------------------------
  gen_inject_error: if FAULT_INJECTION
  generate
    cpu0_idata_seu <= (CPU0_SEU_BIT => inject_error_i(0), others => '0');
    cpu1_idata_seu <= (CPU1_SEU_BIT => inject_error_i(1), others => '0');
    cpu2_idata_seu <= (CPU2_SEU_BIT => inject_error_i(2), others => '0');
  else generate
    cpu0_idata_seu <= (others => '0');
    cpu1_idata_seu <= (others => '0');
    cpu2_idata_seu <= (others => '0');
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
  process(diff_r)
  begin
    if (diff_r /= "000") then
      report "CPU Safety: Difference detected ! diff(2 downto 0) = " & 
             std_logic'image(diff_r(2)) & std_logic'image(diff_r(1)) & std_logic'image(diff_r(0)) 
             severity warning;
    end if;
  end process;

  -- pragma translate_on

end architecture;
