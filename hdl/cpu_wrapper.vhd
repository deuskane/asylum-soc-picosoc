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
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-05-10  1.0      mrosiere Created
-------------------------------------------------------------------------------

library IEEE;
use     IEEE.STD_LOGIC_1164.ALL;
use     IEEE.numeric_std.ALL;

library asylum;
use     asylum.sbi_pkg.all;
use     asylum.WardRV_pkg.all;

entity cpu_wrapper is
  generic (
    CPU_MODEL        : string   := "OpenBlaze8"
   ;HARTID           : std_logic_vector(31 downto 0) := x"00000000"
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
    interrupt_ack_o  : out   std_logic
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
end generate gen_OpenBlaze8;

-------------------------------------------------------------------------------
-- WardRV_fsm - Academic RiscV processor with internal FSM
-------------------------------------------------------------------------------
gen_WardRV_fsm : if CPU_MODEL = "WardRV_fsm" generate
  cpu_WardRV_fsm : entity asylum.sbi_WardRV_fsm
    generic map (
      HARTID               => HARTID,
      RESET_ADDR           => x"00000000",
      IADDR_WIDTH          => iaddr_o'length,
      IADDR_ALIGN_BITS     => 2 -- Word-aligned instructions
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
  end generate gen_WardRV_fsm;

-------------------------------------------------------------------------------
-- Check CPU_MODEL Value
-------------------------------------------------------------------------------
  assert (CPU_MODEL = "OpenBlaze8" or 
          CPU_MODEL = "WardRV_fsm")
    report "Invalid CPU_MODEL: " & CPU_MODEL
    severity failure;

end architecture rtl;
