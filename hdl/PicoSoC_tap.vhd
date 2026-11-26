-------------------------------------------------------------------------------
-- Title      : PicoSoC_tap
-- Project    :
-------------------------------------------------------------------------------
-- File       : PicoSoC_tap.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-11-23
-- Platform   :
-- Standard   : VHDL'2008
-------------------------------------------------------------------------------
-- Description: JTAG TAP of fault injection and status of PicoSoC_top
--              (IDCODE PICOSOC_JTAG_IDCODE_INJECT, IR PICOSOC_JTAG_IR_WIDTH
--              bits, no TRST*), its instruction decoder and 2 test data
--              registers (TCK domain) :
--              * PICOSOC_JTAG_IR_INJECT : jtag_tdr_inout, 3 bits : writes the
--                error injection (bit i : CPU i), reads diff_i
--              * PICOSOC_JTAG_IR_STATUS : jtag_tdr_in, reads status_i
--                (unconstrained : the width comes from the actual, map a
--                signal, GHDL 6.0.0 crashes on an expression)
--              The read values are quasi-static (LEDs, switches, sticky diff,
--              resets) : sampled directly in Capture-DR, without
--              synchronizer (a value that changes during the capture may
--              give a mix of old and new bits)
--              The injection is synchronized on clk_i (2 flip-flops per bit)
--              TCK is resynchronized on clk_i (sync2dffrn, reset arst_b_i)
--              before the TAP, as in cpu_safety and PicoSoC_supervisor for
--              the CPU debug units : the TCK domain is clocked by the
--              resynchronized TCK, never by the TCK pin
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created (injection / status TAP of
--                               PicoSoC_top)
-- 2026-11-26  1.1      mrosiere TCK resynchronized on clk_i, as the CPU
--                               debug units (the TAP lost its state on the
--                               board with the TCK pin as clock)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library asylum;
use     asylum.PicoSoC_pkg.all;
use     asylum.techmap_pkg.all;
use     asylum.jtag_pkg.all;

entity PicoSoC_tap is
  port
    (clk_i            : in  std_logic
    ;arst_b_i         : in  std_logic  -- Power-on reset of the TAP, reset of the synchronizers

    -- JTAG pins of this TAP (one stage of the JTAG chain)
    ;jtag_ini_i       : in  jtag_ini_t
    ;jtag_tgt_o       : out jtag_tgt_t

    -- Values read through JTAG
    ;diff_i           : in  std_logic_vector(3-1 downto 0)
    ;status_i         : in  std_logic_vector

    -- Error injection written through JTAG (synchronized on clk_i, active high)
    ;inject_error_o   : out std_logic_vector(3-1 downto 0)
    );
end entity PicoSoC_tap;

architecture rtl of PicoSoC_tap is

  signal   jtag_tck            : std_logic;  -- TCK resynchronized on clk_i
  signal   jtag_ini            : jtag_ini_t;
  signal   inject_tck          : std_logic;
  signal   inject_trst_b       : std_logic;
  signal   inject_tlr          : std_logic;
  signal   inject_ir           : std_logic_vector(PICOSOC_JTAG_IR_WIDTH-1 downto 0);
  signal   inject_capture_dr   : std_logic;
  signal   inject_shift_dr     : std_logic;
  signal   inject_update_dr    : std_logic;
  signal   inject_tdi          : std_logic;
  signal   inject_user_tdo_en  : std_logic;
  signal   inject_user_tdo     : std_logic;
  signal   sel_inject          : std_logic;
  signal   sel_status          : std_logic;
  signal   tdo_inject          : std_logic;
  signal   tdo_status          : std_logic;
  signal   inject_tck_domain   : std_logic_vector(3-1 downto 0);

begin  -- architecture rtl

  -- TCK resynchronized on clk_i, as in cpu_safety and PicoSoC_supervisor :
  -- every TAP of the JTAG chain sees the same TCK, a bounce on an edge of
  -- TCK shorter than a clock period gives one edge. TMS and TDI are stable
  -- around the edges of TCK. TCK must stay below about clk_i / 8
  ins_jtag_tck_sync : sync2dffrn
    port map
    (clk_i                => clk_i
    ,arst_b_i             => arst_b_i
    ,d_i                  => jtag_ini_i.tck
    ,q_o                  => jtag_tck
    );

  jtag_ini <= (tck    => jtag_tck
              ,trst_n => jtag_ini_i.trst_n
              ,tms    => jtag_ini_i.tms
              ,tdi    => jtag_ini_i.tdi);

  ins_jtag_tap : jtag_tap
    generic map
    (IR_WIDTH             => PICOSOC_JTAG_IR_WIDTH
    ,IDCODE_VALUE         => PICOSOC_JTAG_IDCODE_INJECT
    ,TRST_ENABLE          => false
    )
    port map
    (arst_b_i             => arst_b_i
    ,jtag_ini_i           => jtag_ini
    ,jtag_tgt_o           => jtag_tgt_o
    ,tck_o                => inject_tck
    ,trst_b_o             => inject_trst_b
    ,tlr_o                => inject_tlr
    ,ir_o                 => inject_ir
    ,capture_dr_o         => inject_capture_dr
    ,shift_dr_o           => inject_shift_dr
    ,update_dr_o          => inject_update_dr
    ,tdi_o                => inject_tdi
    ,user_tdo_en_i        => inject_user_tdo_en
    ,user_tdo_i           => inject_user_tdo
    );

  -- Instruction decoder
  sel_inject         <= '1' when inject_ir = PICOSOC_JTAG_IR_INJECT else
                        '0';
  sel_status         <= '1' when inject_ir = PICOSOC_JTAG_IR_STATUS else
                        '0';
  inject_user_tdo_en <= sel_inject or sel_status;
  inject_user_tdo    <= tdo_inject when sel_inject = '1' else
                        tdo_status;

  ins_jtag_tdr_inject : jtag_tdr_inout
    port map
    (tck_i                => inject_tck
    ,trst_b_i             => inject_trst_b
    ,tlr_i                => inject_tlr
    ,sel_i                => sel_inject
    ,capture_dr_i         => inject_capture_dr
    ,shift_dr_i           => inject_shift_dr
    ,update_dr_i          => inject_update_dr
    ,tdi_i                => inject_tdi
    ,tdo_o                => tdo_inject
    ,data_i               => diff_i
    ,data_o               => inject_tck_domain
    );

  ins_jtag_tdr_status : jtag_tdr_in
    port map
    (tck_i                => inject_tck
    ,trst_b_i             => inject_trst_b
    ,sel_i                => sel_status
    ,capture_dr_i         => inject_capture_dr
    ,shift_dr_i           => inject_shift_dr
    ,update_dr_i          => inject_update_dr
    ,tdi_i                => inject_tdi
    ,tdo_o                => tdo_status
    ,data_i               => status_i
    );

  gen_inject_sync: for i in 0 to 3-1
  generate
    ins_inject_sync : sync2dffrn
      port map
      (clk_i              => clk_i
      ,arst_b_i           => arst_b_i
      ,d_i                => inject_tck_domain(i)
      ,q_o                => inject_error_o(i)
      );
  end generate gen_inject_sync;

end architecture rtl;
