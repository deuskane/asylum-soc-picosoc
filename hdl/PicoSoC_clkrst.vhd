-------------------------------------------------------------------------------
-- Title      : PicoSoC_clkrst
-- Project    :
-------------------------------------------------------------------------------
-- File       : PicoSoC_clkrst.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-11-23
-- Platform   :
-- Standard   : VHDL'2008
-------------------------------------------------------------------------------
-- Description: Clock and resets of PicoSoC_top
--              * arst_i (polarity RESET_POLARITY) resynchronized on clk_i :
--                reset of the clock divider
--              * clk_o : clk_i divided by FSYS/FSYS_INT (clock divider, 50 %
--                duty cycle)
--              * arst_b_supervisor_o : the same reset resynchronized on
--                clk_o : power-on reset of the supervisor domain (the board
--                modules, the debug units of the CPUs)
--              * arst_b_supervisor_soc_o : supervisor SoC, also reset by the
--                ndmreset of its debugger
--              * arst_b_user_o : user SoC, reset by the supervisor (or by
--                arst_b_supervisor_o without supervisor) or by the ndmreset
--                of its debugger, resynchronized on clk_o : 2 more cycles of
--                reset with a running clock, so that the registers without
--                reset (input stages of the GPIOs) are loaded before the
--                reset release
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-23  1.0      mrosiere Created (clock and resets of PicoSoC_top)
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
library asylum;
use     asylum.PicoSoC_pkg.all;
use     asylum.techmap_pkg.all;
use     asylum.clock_divider_pkg.all;

entity PicoSoC_clkrst is
  generic
    (FSYS                    : positive := 50_000_000 -- Frequency of clk_i (Hz)
    ;FSYS_INT                : positive := 50_000_000 -- Frequency of clk_o (Hz)
    ;RESET_POLARITY          : string   := "low"      -- Polarity of arst_i : "high" / "low"
    );
  port
    (clk_i                   : in  std_logic
    ;arst_i                  : in  std_logic

    -- SoC clock
    ;clk_o                   : out std_logic

    -- Resets, active low, released on clk_o
    ;arst_b_supervisor_o     : out std_logic -- Supervisor domain, debug units
    ;supervisor_ndmreset_i   : in  std_logic -- ndmreset of the debugger of the supervisor CPU
    ;arst_b_supervisor_soc_o : out std_logic -- Supervisor SoC
    ;arst_b_user_i           : in  std_logic -- Reset of the user SoC by the supervisor
    ;user_ndmreset_i         : in  std_logic -- ndmreset of the debugger of a user CPU
    ;arst_b_user_o           : out std_logic -- User SoC
    );
end entity PicoSoC_clkrst;

architecture rtl of PicoSoC_clkrst is

  signal   arst_b              : std_logic;
  signal   arst_b_sync1        : std_logic;
  signal   arst_b_sync2        : std_logic;
  signal   arst_b_user_req     : std_logic;

begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Reset Management
  -----------------------------------------------------------------------------
  arst_b <= not active_high(arst_i, RESET_POLARITY);

  ins_reset_resynchronizer1 : sync2dffrn
    port map
    (clk_i                => clk_i
    ,arst_b_i             => arst_b
    ,d_i                  => '1'
    ,q_o                  => arst_b_sync1
    );

  ins_reset_resynchronizer2 : sync2dffrn
    port map
    (clk_i                => clk_o
    ,arst_b_i             => arst_b_sync1
    ,d_i                  => '1'
    ,q_o                  => arst_b_sync2
    );

  -----------------------------------------------------------------------------
  -- Clock Management
  -- clk_o is read here (VHDL-2008) : the resynchronizers and the SoCs are on
  -- the same clock signal (no delta cycle between them in simulation)
  -----------------------------------------------------------------------------
  ins_clock_divider : clock_divider
    generic map
    (RATIO                => FSYS/FSYS_INT
    ,ALGO                 => "50%"
     )
    port map
    (clk_i                => clk_i
    ,arstn_i              => arst_b_sync1
    ,cke_i                => '1'
    ,clk_div_o            => clk_o
     );

  -----------------------------------------------------------------------------
  -- Reset of the supervisor SoC : arst_b_sync2, or ndmreset of its debugger
  -----------------------------------------------------------------------------
  arst_b_supervisor_soc_o <= arst_b_sync2 and not supervisor_ndmreset_i;

  -----------------------------------------------------------------------------
  -- Reset of the user SoC (from the supervisor or arst_b_sync2, or ndmreset
  -- of its debugger), resynchronized on clk_o
  -----------------------------------------------------------------------------
  arst_b_user_req <= arst_b_user_i and not user_ndmreset_i;

  ins_reset_resynchronizer_user : sync2dffrn
    port map
    (clk_i                => clk_o
    ,arst_b_i             => arst_b_user_req
    ,d_i                  => '1'
    ,q_o                  => arst_b_user_o
    );

  -----------------------------------------------------------------------------
  -- Outputs
  -----------------------------------------------------------------------------
  arst_b_supervisor_o <= arst_b_sync2;

end architecture rtl;
