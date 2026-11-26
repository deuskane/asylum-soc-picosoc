-------------------------------------------------------------------------------
-- Title      : PicoSoC_inject
-- Project    :
-------------------------------------------------------------------------------
-- File       : PicoSoC_inject.vhd
-- Author     : Mathieu Rosiere
-- Company    :
-- Created    : 2026-11-26
-- Platform   :
-- Standard   : VHDL'2008
-------------------------------------------------------------------------------
-- Description: Error injection of PicoSoC_top : one "trap" per copy of the
--              user CPU (bit i : CPU i), in the power-on reset domain
--              * request : push button (resynchronized here) or injection /
--                status TAP (already synchronized by PicoSoC_tap)
--              * the trap is set by a request, even of one cycle, and flips
--                the instruction bit of its copy (cpu_safety) until it is
--                cleared by :
--                - the detection of the copy : its difference flags
--                  (registered, sticky until the reset of the user SoC) :
--                  lock-step diff(0) for CPU0 and CPU1 ; TMR the two pairs
--                  of the copy (CPU0 : diff(0) and diff(2), CPU1 : diff(0)
--                  and diff(1), CPU2 : diff(1) and diff(2)) ; never without
--                  safety
--                - a falling edge (1 -> 0) of the request of the TAP
--              * clear wins over set in the same cycle : while the flags of
--                a copy are set, a held request does not set its trap ; after
--                the reset of the user SoC (flags cleared) it sets it again
--              * the reset of the user SoC does not clear a trap
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-26  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
library asylum;
use     asylum.techmap_pkg.all;

entity PicoSoC_inject is
  generic
    (SAFETY           : string := "lock-step" -- "none" / "lock-step" / "tmr"
    );
  port
    (clk_i            : in  std_logic
    ;arst_b_i         : in  std_logic  -- Power-on reset (not the reset of the user SoC)

    -- Requests, active high : push buttons (asynchronous), TAP (synchronous)
    ;button_i         : in  std_logic_vector(3-1 downto 0)
    ;jtag_i           : in  std_logic_vector(3-1 downto 0)

    -- Registered difference flags of the user SoC (bit 0 : CPU0 vs CPU1,
    -- 1 : CPU1 vs CPU2, 2 : CPU2 vs CPU0)
    ;diff_i           : in  std_logic_vector(3-1 downto 0)

    -- Error injected in each copy (the traps)
    ;inject_error_o   : out std_logic_vector(3-1 downto 0)
    );
end entity PicoSoC_inject;

architecture rtl of PicoSoC_inject is

  signal   button              : std_logic_vector(3-1 downto 0); -- Resynchronized push buttons
  signal   jtag_r              : std_logic_vector(3-1 downto 0); -- Request of the TAP, previous cycle
  signal   detected            : std_logic_vector(3-1 downto 0); -- Copy i seen different by the compare
  signal   clear               : std_logic_vector(3-1 downto 0);
  signal   trap_r              : std_logic_vector(3-1 downto 0);

begin  -- architecture rtl

  gen_button_sync: for i in 0 to 3-1
  generate
    ins_button_sync : sync2dffrn
      port map
      (clk_i              => clk_i
      ,arst_b_i           => arst_b_i
      ,d_i                => button_i(i)
      ,q_o                => button(i)
      );
  end generate gen_button_sync;

  -- Copy i detected : every pair of copy i that is compared is flagged
  gen_tmr: if SAFETY = "tmr"
  generate
    detected <= (0 => diff_i(0) and diff_i(2)
                ,1 => diff_i(0) and diff_i(1)
                ,2 => diff_i(1) and diff_i(2));
  elsif SAFETY = "lock-step"
  generate
    detected <= (0 => diff_i(0)
                ,1 => diff_i(0)
                ,2 => '0');
  else generate
    detected <= (others => '0');
  end generate gen_tmr;

  clear <= detected or (jtag_r and not jtag_i);

  process (clk_i, arst_b_i) is
  begin
    if arst_b_i = '0'
    then
      jtag_r <= (others => '0');
      trap_r <= (others => '0');
    elsif rising_edge(clk_i)
    then
      jtag_r <= jtag_i;
      trap_r <= (trap_r or button or jtag_i) and not clear;
    end if;
  end process;

  inject_error_o <= trap_r;

end architecture rtl;
