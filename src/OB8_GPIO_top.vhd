-------------------------------------------------------------------------------
-- Title      : OB8_GPIO
-- Project    : 
-------------------------------------------------------------------------------
-- File       : OB8_GPIO.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2025-01-15
-- Last update: 2025-01-21
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2017 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2025-01-15  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.pbi_pkg.all;

entity OB8_GPIO_top is
  generic (
    FSYS             : positive := 50_000_000;
    FSYS_INT         : positive := 50_000_000;
    BAUD_RATE        : integer  := 115200;
    NB_SWITCH        : positive := 8;
    NB_LED           : positive := 19;
    RESET_POLARITY   : string   := "low";       -- "high" / "low"
    SUPERVISOR       : boolean  := True ;
    SAFETY           : string   := "lock-step"; -- "none" / "lock-step" / "tmr"
    FAULT_INJECTION  : boolean  := True ; 
    IT_USER_POLARITY : string   := "low";       -- "high" / "low"
    FAULT_POLARITY   : string   := "low"        -- "high" / "low"

    );
  port (
    clk_i          : in  std_logic;
    arst_i         : in  std_logic;

    switch_i       : in  std_logic_vector(NB_SWITCH-1 downto 0);
    led_o          : out std_logic_vector(NB_LED   -1 downto 0);
    it_user_i      : in  std_logic;

    uart_tx_o      : out std_logic;
    uart_rx_i      : in  std_logic;
    
    inject_error_i : in  std_logic_vector(        3-1 downto 0)
    );
end OB8_GPIO_top;
  
architecture rtl of OB8_GPIO_top is

  constant NB_LED0                      : positive := 8;
  constant NB_LED1                      : positive := 8;
  constant NB_LED2                      : positive := 3;
  
  signal   clk                          : std_logic;
  signal   arst_b                       : std_logic;
  signal   arst_b_sync                  : std_logic;
  signal   led0                         : std_logic_vector(NB_LED0-1 downto 0);
  signal   led1                         : std_logic_vector(NB_LED1-1 downto 0);
  signal   led2                         : std_logic_vector(NB_LED2-1 downto 0);
           
  signal   arst_b_supervisor            : std_logic;
  signal   arst_b_user                  : std_logic_vector(1-1 downto 0);
           
  signal   diff                         : std_logic_vector(3-1 downto 0);
           
  signal   it_user                      : std_logic;
  signal   it_user_sync                 : std_logic;
  signal   inject_error                 : std_logic_vector(3-1 downto 0);

--signal   uart_baud_tick               : std_logic;
--signal   uart_tx                      : std_logic;
begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Reset Management
  -----------------------------------------------------------------------------
  gen_arst_b:
  if RESET_POLARITY = "low"
  generate
    arst_b <=     arst_i;
  end generate gen_arst_b;

  gen_arst:
  if RESET_POLARITY = "high"
  generate
    arst_b <= not arst_i;
  end generate gen_arst;

  ins_reset_resynchronizer : entity work.sync2dffrn(rtl)
    port map(
    clk_i    => clk_i     ,
    arst_b_i => arst_b    ,
    d_i      => '1'       ,
    q_o      => arst_b_sync
    );

  arst_b_supervisor <= arst_b_sync;

  -----------------------------------------------------------------------------
  -- Clock Management
  -----------------------------------------------------------------------------
  ins_clock_divider : entity work.clock_divider(rtl)
    generic map(
      RATIO            => FSYS/FSYS_INT
      )
    port map (
      clk_i            => clk_i            ,
      arstn_i          => arst_b_supervisor,
      cke_i            => '1'              ,
      clk_div_o        => clk
      );

  -----------------------------------------------------------------------------
  -- Input synchronization
  -----------------------------------------------------------------------------
  ins_it_user : entity work.sync2dff(rtl)
    port map
    (clk_i    => clk
    ,d_i      => it_user
    ,q_o      => it_user_sync
    );

  -----------------------------------------------------------------------------
  -- SoC User
  -----------------------------------------------------------------------------
  ins_soc_user : entity work.OB8_GPIO_user(rtl)
    generic map(
    CLOCK_FREQ      => FSYS_INT    ,
    BAUD_RATE       => BAUD_RATE   ,
    NB_SWITCH       => NB_SWITCH   ,
    NB_LED0         => NB_LED0     ,
    NB_LED1         => NB_LED1     ,
    SAFETY          => SAFETY      ,
    FAULT_INJECTION => FAULT_INJECTION
    )
  port map(
    clk_i          => clk,
    arst_b_i       => arst_b_user(0),
    switch_i       => switch_i,
    led0_o         => led0,
    led1_o         => led1,
    uart_tx_o      => uart_tx_o,
    uart_rx_i      => uart_rx_i,
    it_i           => it_user_sync,
    diff_o         => diff,
    inject_error_i => inject_error
    );

  -----------------------------------------------------------------------------
  -- SoC Supervisor
  -----------------------------------------------------------------------------
  gen_supervisor: if SUPERVISOR = True
  generate
    ins_soc_supervisor : entity work.OB8_GPIO_supervisor(rtl)
      generic map(
        NB_LED0   => 1,
        NB_LED1   => 3
        )
      port map(
        clk_i      => clk,
        arst_b_i   => arst_b_supervisor,
        led0_o     => arst_b_user,
        led1_o     => led2,
        diff_i     => diff 
        );

  end generate gen_supervisor;

  gen_supervisor_n: if SUPERVISOR = False
  generate
    arst_b_user(0) <= arst_b_supervisor;
  --led2           <= (others => '0');
    led2           <= diff;
  end generate gen_supervisor_n;
  
  -----------------------------------------------------------------------------
  -- LED
  -----------------------------------------------------------------------------
  led_o <= led1 & led2 & led0;

  -----------------------------------------------------------------------------
  -- IT_USER User
  -----------------------------------------------------------------------------
  gen_it_user_b:
  if IT_USER_POLARITY = "low"
  generate
    it_user <= not it_user_i;
  end generate gen_it_user_b;

  gen_it_user:
  if IT_USER_POLARITY = "high"
  generate
    it_user <=     it_user_i;
  end generate gen_it_user;

  -----------------------------------------------------------------------------
  -- FAULT_INJECTION
  -----------------------------------------------------------------------------
  gen_inject_error_b:
  if FAULT_POLARITY = "low"
  generate
    inject_error <= not inject_error_i;
  end generate gen_inject_error_b;

  gen_inject_error:
  if FAULT_POLARITY = "high"
  generate
    inject_error <=     inject_error_i;
  end generate gen_inject_error;


--ins_uart_baud_rate_gen : entity work.uart_baud_rate_gen(rtl)
--  generic map(
--    BAUD_RATE      => 115200,
--    CLOCK_FREQ     => FSYS_INT
--    )
--  port map(
--    clk_i          => clk,
--    arst_b_i       => arst_b_supervisor,
--    baud_tick_en_i => '1',
--    baud_tick_o    => uart_baud_tick
--    );
--
--ins_uart_tx_axis : entity work.uart_tx_axis(rtl)
--  generic map
--  ( WIDTH           => 8
--    )
--  port map
--  ( clk_i           => clk
--   ,arst_b_i        => arst_b_supervisor
--   ,s_axis_tdata_i  => x"30"
--   ,s_axis_tvalid_i => '1'
--   ,s_axis_tready_o => open
--   ,uart_tx_o       => uart_tx
--   ,baud_tick_i     => uart_baud_tick
--   ,parity_enable_i => '0'
--   ,parity_odd_i    => '0'
--    );
--
--ins_uart_rx_axis : entity work.uart_rx_axis(rtl)
--  generic map
--  ( WIDTH           => 8
--    )
--  port map
--  ( clk_i           => clk
--   ,arst_b_i        => arst_b_supervisor
--   ,m_axis_tdata_o  => open
--   ,m_axis_tvalid_o => open
--   ,m_axis_tready_i => '1'
--   ,uart_rx_i       => uart_tx
--   ,baud_tick_i     => uart_baud_tick
--   ,parity_enable_i => '0'
--   ,parity_odd_i    => '0'
--    );
--
--uart_tx_o <= uart_tx;
  
end architecture rtl;
