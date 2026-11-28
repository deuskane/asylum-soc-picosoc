-------------------------------------------------------------------------------
-- Title      : cpu_wrapper
-- Project    : 
-------------------------------------------------------------------------------
-- File       : cpu_wrapper.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2026-05-10
-- Last update: 2026-05-10
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: The CPU of PicoSoC : sbi_OpenBlaze8 or sbi_WardRV_fsm
--              (CPU_MODEL), with DEBUG_ENABLE the debug unit of WardRV_fsm.
--              inject_i : error injection inside the CPU, 4 requests (e.g.
--              bits 2:0 : the copies of a TMR register, bit 3 : the register
--              file), a pulse of one clock cycle per injection (INJECT of
--              the injection / status TAP : [7:4], [11:8], [15:12] for the
--              CPU copy 0, 1, 2, see cpu_safety). Unused by the reference CPUs : free for a
--              hardened CPU, connect it to your injection.
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-05-10  1.0      mrosiere Created
-- 2026-11-22  1.1      mrosiere DEBUG_ENABLE : debug unit WardRV_debug of
--                               WardRV_fsm, JTAG pins ; OpenBlaze8 or no debug
--                               unit : TDO = TDI (no bit in the JTAG chain)
-- 2026-11-27  1.2      mrosiere inject_i (unused : injection inside a
--                               hardened CPU)
-- 2026-11-28  1.3      mrosiere inject_i of 4 bits (bit 3 : e.g. the register
--                               file)
-------------------------------------------------------------------------------

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.numeric_std.ALL;

library asylum;
use     asylum.sbi_pkg.all;
use     asylum.WardRV_pkg.all;
use     asylum.WardRV_debug_pkg.all;
use     asylum.jtag_pkg.all;

entity cpu_wrapper is
  generic (
    CPU_MODEL        : string   := "OpenBlaze8"
   ;HARTID           : std_logic_vector(31 downto 0) := x"00000000"
   ;DEBUG_ENABLE     : boolean  := false -- WardRV_fsm only : debug unit WardRV_debug (RISC-V Debug Spec), its TAP
   ;IDCODE_VALUE     : std_logic_vector(31 downto 0) := x"10000001" -- IDCODE of the TAP (DEBUG_ENABLE)
  );
  port   (
    clk_i            : in    std_logic;
    cke_i            : in    std_logic;
    arst_b_i         : in    std_logic; -- asynchronous reset

    -- Instructions
    ics_o            : out   std_logic;
    iaddr_o          : out   std_logic_vector;
    idata_i          : in    std_logic_vector;
    
    -- Bus
    sbi_ini_o        : out   sbi_ini_t;
    sbi_tgt_i        : in    sbi_tgt_t;

    -- To/From IT Ctrl
    interrupt_i      : in    std_logic;
    interrupt_ack_o  : out   std_logic;

    -- Error injection inside the CPU : 4 requests (e.g. bits 2:0 the copies
    -- of a TMR register, bit 3 the register file), one clock cycle per
    -- injection. Unused here : free for a hardened CPU, connect it to your
    -- injection
    inject_i         : in    std_logic_vector(4-1 downto 0) := "0000";

    -- Debug unit (DEBUG_ENABLE) : JTAG pins, power-on reset of the debug
    -- unit (not the CPU reset), ndmreset (request to reset the CPU and its SoC)
    dbg_arst_b_i     : in    std_logic := '1';
    jtag_ini_i       : in    jtag_ini_t;
    jtag_tgt_o       : out   jtag_tgt_t;
    ndmreset_o       : out   std_logic
    );
  
end entity cpu_wrapper;

architecture rtl of cpu_wrapper is
begin  -- architecture rtl

-------------------------------------------------------------------------------
-- OpenBlaze8 - Xilinx PicoBlaze3 clone
-------------------------------------------------------------------------------
gen_OpenBlaze8 : if CPU_MODEL = "OpenBlaze8" generate
  cpu_OpenBlaze8 : entity asylum.sbi_OpenBlaze8
    generic map (
      RAM_DEPTH            => 256,
      REGFILE_SYNC_READ    => true
     )
    port map (
      clk_i                => clk_i,
      cke_i                => cke_i,
      arstn_i              => arst_b_i,

      -- Instructions
      ics_o                => ics_o,
      iaddr_o              => iaddr_o,
      idata_i              => idata_i,
      
      -- Bus
      sbi_ini_o            => sbi_ini_o,
      sbi_tgt_i            => sbi_tgt_i,

      -- To/From IT Ctrl
      interrupt_i          => interrupt_i,
      interrupt_ack_o      => interrupt_ack_o
    );

  -- No debug unit : a wire in the JTAG chain, TDO never driven
  jtag_tgt_o <= (tdo => jtag_ini_i.tdi, tdo_en => '0');
  ndmreset_o <= '0';
end generate gen_OpenBlaze8;

-------------------------------------------------------------------------------
-- WardRV_fsm - Academic RiscV processor with internal FSM
-------------------------------------------------------------------------------
gen_WardRV_fsm : if CPU_MODEL = "WardRV_fsm" generate
  -- Core <-> Debug Module
  signal dbg_hart_req : dbg_hart_req_t;
  signal dbg_mem_ini  : dmem_ini_t;
  signal dbg_mem_tgt  : dmem_tgt_t;
begin
  cpu_WardRV_fsm : entity asylum.sbi_WardRV_fsm
    generic map (
      HARTID               => HARTID,
      RESET_ADDR           => x"00000000",
      IADDR_WIDTH          => iaddr_o'length,
      IADDR_ALIGN_BITS     => 2, -- Word-aligned instructions
      DEBUG_ENABLE         => DEBUG_ENABLE
     )
    port map (
      clk_i                => clk_i,
      cke_i                => cke_i,
      arstn_i              => arst_b_i,

      -- Instructions
      ics_o                => ics_o,
      iaddr_o              => iaddr_o,
      idata_i              => idata_i,
      
      -- Bus
      sbi_ini_o            => sbi_ini_o,
      sbi_tgt_i            => sbi_tgt_i,

      -- To/From IT Ctrl
      interrupt_i          => interrupt_i,
      interrupt_ack_o      => interrupt_ack_o,

      -- Debug
      dbg_hart_req_i       => dbg_hart_req,
      dbg_mem_ini_o        => dbg_mem_ini,
      dbg_mem_tgt_i        => dbg_mem_tgt
    );

  -- Debug unit : TAP, DTM and Debug Module (program buffer 2, data 2, no
  -- system bus access, no TRST*). Power-on reset dbg_arst_b_i, the CPU reset
  -- is its hart reset
  gen_debug : if DEBUG_ENABLE generate
    ins_WardRV_debug : entity asylum.WardRV_debug
      generic map (
        IDCODE_VALUE         => IDCODE_VALUE,
        TRST_ENABLE          => false
       )
      port map (
        jtag_ini_i           => jtag_ini_i,
        jtag_tgt_o           => jtag_tgt_o,
        clk_i                => clk_i,
        arst_b_i             => dbg_arst_b_i,
        hart_rst_b_i         => arst_b_i,
        dbg_hart_req_o       => dbg_hart_req,
        dbg_mem_ini_i        => dbg_mem_ini,
        dbg_mem_tgt_o        => dbg_mem_tgt,
        ndmreset_o           => ndmreset_o,
        sba_dmem_ini_o       => open
      );
  end generate gen_debug;

  -- No debug unit : a wire in the JTAG chain, TDO never driven
  gen_debug_b : if not DEBUG_ENABLE generate
    dbg_hart_req <= DBG_HART_REQ_NULL;
    dbg_mem_tgt  <= DMEM_TGT_NULL;
    jtag_tgt_o   <= (tdo => jtag_ini_i.tdi, tdo_en => '0');
    ndmreset_o   <= '0';
  end generate gen_debug_b;
  end generate gen_WardRV_fsm;

-------------------------------------------------------------------------------
-- Check CPU_MODEL Value
-------------------------------------------------------------------------------
  assert (CPU_MODEL = "OpenBlaze8" or 
          CPU_MODEL = "WardRV_fsm")
    report "Invalid CPU_MODEL: " & CPU_MODEL
    severity failure;

  assert (not DEBUG_ENABLE or CPU_MODEL = "WardRV_fsm")
    report "DEBUG_ENABLE needs CPU_MODEL WardRV_fsm (" & CPU_MODEL & ")"
    severity failure;

end architecture rtl;
