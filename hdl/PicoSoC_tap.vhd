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
--              * PICOSOC_JTAG_IR_INJECT : jtag_tdr_inout, 16 bits, a nibble
--                per target :
--                - written [2:0] : the error injection outside the CPUs (bit
--                  i : copy i, the instruction bit SEU_BIT, trapped in
--                  PicoSoC_inject), a level (a 1 -> 0 clears the trap) ;
--                - written [6:4], [10:8], [14:12] : the error injection
--                  inside the CPU copy 0, 1, 2 : the bit 4+4*i+k is the
--                  injection request k of copy i (e.g. the copy k of a TMR
--                  register of that CPU), a pulse of one clk_i cycle on
--                  inject_cpu_o(3*i+k) for each 0 -> 1 of the bit (one error
--                  per write) ;
--                - written [3], [7], [11], [15] : reserved (write 0) ;
--                - read : diff_i in [2:0], 0 above
--              * PICOSOC_JTAG_IR_STATUS : jtag_tdr_in, reads status_i
--                (unconstrained : the width comes from the actual, map a
--                signal, GHDL 6.0.0 crashes on an expression)
--              The read values are quasi-static (LEDs, switches, sticky diff,
--              resets) : sampled directly in Capture-DR, without
--              synchronizer (a value that changes during the capture may
--              give a mix of old and new bits)
--              The injection is synchronized on clk_i (2 flip-flops per bit ;
--              inside the CPUs : then a register, the pulse on its rising
--              edge)
--              jtag_ini_i.tck is already resynchronized on clk_i by
--              PicoSoC_top (one synchronizer for the whole JTAG chain) : the
--              TCK domain is never clocked by the TCK pin
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
-- 2026-11-26  1.2      mrosiere Synchronizer of TCK removed : jtag_ini_i.tck
--                               resynchronized once for the whole chain in
--                               PicoSoC_top
-- 2026-11-27  1.3      mrosiere INJECT of 16 bits : 3 bits of injection
--                               inside each CPU copy (inject_cpu_o, a pulse
--                               per 0 -> 1)
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

    -- Error injection written through JTAG (synchronized on clk_i, active
    -- high) : outside the CPUs (bit i : copy i, a level), inside the CPUs
    -- (bits 3*i+2 downto 3*i : copy i, a pulse of one cycle for each 0 -> 1
    -- of a bit)
    ;inject_error_o   : out std_logic_vector(3-1 downto 0)
    ;inject_cpu_o     : out std_logic_vector(9-1 downto 0)
    );
end entity PicoSoC_tap;

architecture rtl of PicoSoC_tap is

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
  signal   inject_tck_domain   : std_logic_vector(16-1 downto 0); -- [2:0] outside, [4+4*i+2:4+4*i] inside the CPU i
  signal   diff_capture        : std_logic_vector(16-1 downto 0);
  signal   inject_cpu          : std_logic_vector(9-1 downto 0);  -- Inside the CPUs, synchronized (3*i+k : CPU i, bit k)
  signal   inject_cpu_r        : std_logic_vector(9-1 downto 0);

begin  -- architecture rtl

  ins_jtag_tap : jtag_tap
    generic map
    (IR_WIDTH             => PICOSOC_JTAG_IR_WIDTH
    ,IDCODE_VALUE         => PICOSOC_JTAG_IDCODE_INJECT
    ,TRST_ENABLE          => false
    )
    port map
    (arst_b_i             => arst_b_i
    ,jtag_ini_i           => jtag_ini_i
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
    ,data_i               => diff_capture
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

  -- Capture of INJECT : the difference flags, 0 above
  diff_capture <= "0000000000000" & diff_i;

  gen_inject_sync: for i in 0 to 3-1
  generate
    ins_inject_sync : sync2dffrn
      port map
      (clk_i              => clk_i
      ,arst_b_i           => arst_b_i
      ,d_i                => inject_tck_domain(i)
      ,q_o                => inject_error_o(i)
      );

    gen_inject_cpu_sync: for k in 0 to 3-1
    generate
      ins_inject_cpu_sync : sync2dffrn
        port map
        (clk_i            => clk_i
        ,arst_b_i         => arst_b_i
        ,d_i              => inject_tck_domain(4+4*i+k)
        ,q_o              => inject_cpu(3*i+k)
        );
    end generate gen_inject_cpu_sync;
  end generate gen_inject_sync;

  -- Injection inside the CPUs : one pulse of one cycle per 0 -> 1
  process (clk_i, arst_b_i) is
  begin
    if arst_b_i = '0'
    then
      inject_cpu_r <= (others => '0');
    elsif rising_edge(clk_i)
    then
      inject_cpu_r <= inject_cpu;
    end if;
  end process;

  inject_cpu_o <= inject_cpu and not inject_cpu_r;

end architecture rtl;
