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
--                - the detection of the copy : a rising edge (0 -> 1) of
--                  any difference flag of the copy (registered, sticky until
--                  the reset of the user SoC) : CPU0 diff(0) or diff(2),
--                  CPU1 diff(0) or diff(1), CPU2 diff(1) or diff(2) ; the
--                  same rule for lock-step (only diff(0)) and TMR, never
--                  without safety (no flag)
--                - a falling edge (1 -> 0) of the request of the TAP
--              * clear wins over set in the same cycle (the edge cycle
--                only) : a request held or made after the detection sets the
--                trap again (in TMR, the second error stays injectable while
--                the flags of the first one are still set)
--              * the reset of the user SoC does not clear a trap
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2026-11-26  1.0      mrosiere Created
-- 2026-11-26  1.1      mrosiere Clear on the rising edge of any difference
--                               flag of the copy, the same for lock-step and
--                               TMR (was the level ; TMR : both pairs) ;
--                               SAFETY removed
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
library asylum;
use     asylum.techmap_pkg.all;

entity PicoSoC_inject is
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
  signal   diff_r              : std_logic_vector(3-1 downto 0); -- Difference flags, previous cycle
  signal   diff_rise           : std_logic_vector(3-1 downto 0); -- Difference flags, 0 -> 1
  signal   detected            : std_logic_vector(3-1 downto 0); -- Copy i newly seen different by the compare
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

  -- Copy i detected : a rising edge of any flag of a pair of copy i (the
  -- flags that do not exist, lock-step diff(1) and diff(2), without safety
  -- all, stay 0)
  diff_rise <= diff_i and not diff_r;
  detected  <= (0 => diff_rise(0) or diff_rise(2)
               ,1 => diff_rise(0) or diff_rise(1)
               ,2 => diff_rise(1) or diff_rise(2));

  clear <= detected or (jtag_r and not jtag_i);

  process (clk_i, arst_b_i) is
  begin
    if arst_b_i = '0'
    then
      jtag_r <= (others => '0');
      diff_r <= (others => '0');
      trap_r <= (others => '0');
    elsif rising_edge(clk_i)
    then
      jtag_r <= jtag_i;
      diff_r <= diff_i;
      trap_r <= (trap_r or button or jtag_i) and not clear;
    end if;
  end process;

  inject_error_o <= trap_r;

end architecture rtl;
