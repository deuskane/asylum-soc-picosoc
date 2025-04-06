-------------------------------------------------------------------------------
-- Title      : OB8_GPIO
-- Project    : 
-------------------------------------------------------------------------------
-- File       : OB8_GPIO.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2025-04-06
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2017 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2017-03-30  1.0      mrosiere Created
-- 2024-12-31  1.1      mrosiere Fix parameter to GPIO
-- 2025-01-12  2.0      mrosiere Add Safety feature
-- 2025-01-15  2.1      mrosiere Update diff detection
-- 2025-01-21  2.2      mrosiere Add UART
-- 2025-04-02  2.3      mrosiere Use ICN
-------------------------------------------------------------------------------


library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library work;
use     work.pbi_pkg.all;
use     work.GPIO_csr_pkg.all;
use     work.UART_csr_pkg.all;

entity OB8_GPIO_user is
    generic (
    CLOCK_FREQ     : integer  := 50000000;
    BAUD_RATE      : integer  := 115200;
    NB_SWITCH      : positive := 8;
    NB_LED0        : positive := 8;
    NB_LED1        : positive := 8;
    SAFETY         : string   := "lock-step"; -- "none" / "lock-step" / "tmr"
    FAULT_INJECTION: boolean  := False
    );
  port (
    clk_i          : in  std_logic;
    arst_b_i       : in  std_logic;
                   
    switch_i       : in  std_logic_vector(NB_SWITCH-1 downto 0);
    led0_o         : out std_logic_vector(NB_LED0  -1 downto 0);
    led1_o         : out std_logic_vector(NB_LED1  -1 downto 0);

    uart_tx_o      : out std_logic;
    uart_rx_i      : in  std_logic;
    

    it_i           : in  std_logic;
    inject_error_i : in  std_logic_vector(        3-1 downto 0);
    diff_o         : out std_logic_vector(        3-1 downto 0)  -- bit 0 : cpu0 vs cpu1
                                                                 -- bit 1 : cpu1 vs cpu2
                                                                 -- bit 2 : cpu2 vs cpu0
    );
end OB8_GPIO_user;

architecture rtl of OB8_GPIO_user is

  -- Constant declaration
  constant CST0                       : std_logic_vector (8-1 downto 0) := (others => '0');
  constant CST1                       : std_logic_vector (8-1 downto 0) := (others => '1');

  -- Module parameters
  constant CPU1_ENABLE                : boolean := ((SAFETY = "lock-step") or
                                                    (SAFETY = "tmr"));
  constant CPU2_ENABLE                : boolean := ((SAFETY = "tmr"));

  -- ICN Configuration
  constant NB_TARGET                  : positive := 4;

  constant TARGET_SWITCH              : integer  := 0;
  constant TARGET_LED0                : integer  := 1;
  constant TARGET_LED1                : integer  := 2;
  constant TARGET_UART                : integer  := 3;
  
  constant TARGET_ID                  : pbi_addrs_t   (NB_TARGET-1 downto 0) :=
    ( TARGET_SWITCH                   => "00010000",
      TARGET_LED0                     => "00100000",
      TARGET_LED1                     => "01000000",
      TARGET_UART                     => "10000000" 
      );

  constant TARGET_ADDR_WIDTH          : naturals_t    (NB_TARGET-1 downto 0) :=
    ( TARGET_SWITCH                   => GPIO_ADDR_WIDTH,
      TARGET_LED0                     => GPIO_ADDR_WIDTH,
      TARGET_LED1                     => GPIO_ADDR_WIDTH,
      TARGET_UART                     => UART_ADDR_WIDTH
      );

  constant TARGET_ADDR_ENCODING       : string := "one_hot";
  
  -- Signals ICN
  signal icn_pbi_inis                 : pbi_inis_t(NB_TARGET-1 downto 0)(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                                         wdata(PBI_DATA_WIDTH-1 downto 0));
  signal icn_pbi_tgts                 : pbi_tgts_t(NB_TARGET-1 downto 0)(rdata(PBI_DATA_WIDTH-1 downto 0));

  -- Signals Clock/Reset
  signal clk                          : std_logic;
  signal arst_b                       : std_logic;

  -- Signals CPUs
  signal cpu0_iaddr                   : std_logic_vector(10-1 downto 0);
  signal cpu0_idata                   : std_logic_vector(18-1 downto 0);
  signal cpu0_pbi_ini                 : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal cpu0_it_ack                  : std_logic;
  
  signal cpu1_iaddr                   : std_logic_vector(10-1 downto 0);
  signal cpu1_idata                   : std_logic_vector(18-1 downto 0);
  signal cpu1_pbi_ini                 : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal cpu1_it_ack                  : std_logic;

  signal cpu2_iaddr                   : std_logic_vector(10-1 downto 0);
  signal cpu2_idata                   : std_logic_vector(18-1 downto 0);
  signal cpu2_pbi_ini                 : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal cpu2_it_ack                  : std_logic;

  -- Signals CPU (post lockstep / TMR)
  signal cpu_iaddr                    : std_logic_vector(10-1 downto 0);
  signal cpu_idata                    : std_logic_vector(18-1 downto 0);

  signal cpu_pbi_ini                  : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal cpu_pbi_tgt                  : pbi_tgt_t(rdata(PBI_DATA_WIDTH-1 downto 0));
  signal cpu_it_val                   : std_logic;
  signal cpu_it_ack                   : std_logic;

  -- Signals Safety
  signal diff                         : std_logic_vector(3-1 downto 0); -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0
  signal diff_r                       : std_logic_vector(3-1 downto 0); -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0

begin  -- architecture rtl

  -----------------------------------------------------------------------------
  -- Clock & Reset
  -----------------------------------------------------------------------------
  clk    <= clk_i;
  arst_b <= arst_b_i;

  -----------------------------------------------------------------------------
  -- Interruption
  --
  -- From level to Val/Ack interruption
  -----------------------------------------------------------------------------
  ins_it_ctrl : entity work.it_ctrl(rtl)
  port map(
    clk_i    => clk          ,
    arstn_i  => arst_b       ,
    it_i     => it_i         ,
    it_val_o => cpu_it_val   ,
    it_ack_i => cpu_it_ack
    );
  
  -----------------------------------------------------------------------------
  -- CPU 0
  -----------------------------------------------------------------------------
  ins_pbi_OpenBlaze8_0 : entity work.pbi_OpenBlaze8(rtl)
  port map (
    clk_i            => clk         ,
    cke_i            => '1'         ,
    arstn_i          => arst_b      ,
    iaddr_o          => cpu0_iaddr  ,
    idata_i          => cpu0_idata  ,
    pbi_ini_o        => cpu0_pbi_ini,
    pbi_tgt_i        => cpu_pbi_tgt ,
    interrupt_i      => cpu_it_val  ,
    interrupt_ack_o  => cpu0_it_ack
    );

  -----------------------------------------------------------------------------
  -- CPU ROM
  -----------------------------------------------------------------------------
  ins_pbi_OpenBlaze8_ROM : entity work.ROM_user(rom)
    port map (
      clk_i            => clk      ,
      cke_i            => '1'      ,
      address_i        => cpu_iaddr,
      instruction_o    => cpu_idata
    );

  -----------------------------------------------------------------------------
  -- CPU Signals
  --  * ROM interface
  --  * ICN interface
  --  * IT  interface
  --
  -- If safety none or lock-step : take cpu 0
  -- else if tmr : vote all cpu output
  -----------------------------------------------------------------------------
  gen_cpu_vote: if SAFETY = "tmr"
  generate
    cpu_iaddr     <= ((cpu0_iaddr   and cpu1_iaddr  ) or
                      (cpu1_iaddr   and cpu2_iaddr  ) or
                      (cpu2_iaddr   and cpu0_iaddr  ));
    cpu_pbi_ini   <= ((cpu0_pbi_ini and cpu1_pbi_ini) or
                      (cpu1_pbi_ini and cpu2_pbi_ini) or
                      (cpu2_pbi_ini and cpu0_pbi_ini));
    cpu_it_ack    <= ((cpu0_it_ack  and cpu1_it_ack ) or
                      (cpu1_it_ack  and cpu2_it_ack ) or
                      (cpu2_it_ack  and cpu0_it_ack ));
  end generate;

  gen_cpu_vote_b: if SAFETY /= "tmr"
  generate
    cpu_iaddr      <= cpu0_iaddr   ;
    cpu_pbi_ini    <= cpu0_pbi_ini ;
    cpu_it_ack     <= cpu0_it_ack  ;
  end generate;
  
  -----------------------------------------------------------------------------
  -- Interconnect
  -- From 1 Initiator to N Target
  -----------------------------------------------------------------------------
  ins_pbi_icn : entity work.pbi_icn(rtl)
    generic map (
      NB_TARGET            => NB_TARGET,
      TARGET_ID            => TARGET_ID,
      TARGET_ADDR_WIDTH    => TARGET_ADDR_WIDTH,
      TARGET_ADDR_ENCODING => TARGET_ADDR_ENCODING
      )
    port map (
      clk_i            => clk         ,
      cke_i            => '1'         ,
      arst_b_i         => arst_b      ,
      pbi_ini_i        => cpu_pbi_ini ,
      pbi_tgt_o        => cpu_pbi_tgt ,
      pbi_inis_o       => icn_pbi_inis,
      pbi_tgts_i       => icn_pbi_tgts
    );

  -----------------------------------------------------------------------------
  -- GPIO 0 - Switch
  -----------------------------------------------------------------------------
  ins_pbi_switch : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => NB_SWITCH,
    DATA_OE_INIT     => CST0(NB_SWITCH-1 downto 0),
    DATA_OE_FORCE    => CST1(NB_SWITCH-1 downto 0),
    IT_ENABLE        => false
    )
  port map  (
    clk_i            => clk           ,
    cke_i            => '1'           ,
    arstn_i          => arst_b         ,
    pbi_ini_i        => icn_pbi_inis(TARGET_SWITCH)   ,
    pbi_tgt_o        => icn_pbi_tgts(TARGET_SWITCH)   ,
    data_i           => switch_i      ,
    data_o           => open          ,
    data_oe_o        => open          ,
    interrupt_o      => open          ,
    interrupt_ack_i  => '0'
    );

  -----------------------------------------------------------------------------
  -- GPIO 1 - LED
  -----------------------------------------------------------------------------
  ins_pbi_led0 : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => NB_LED0,
    DATA_OE_INIT     => CST1(NB_LED0-1 downto 0),
    DATA_OE_FORCE    => CST1(NB_LED0-1 downto 0),
    IT_ENABLE        => false
    )
  port map  (
    clk_i            => clk         ,
    cke_i            => '1'         ,
    arstn_i          => arst_b       ,
    pbi_ini_i        => icn_pbi_inis(TARGET_LED0) ,
    pbi_tgt_o        => icn_pbi_tgts(TARGET_LED0) ,
    data_i           => X"00"       ,
    data_o           => led0_o      ,
    data_oe_o        => open        ,
    interrupt_o      => open        ,
    interrupt_ack_i  => '0'
    );

  -----------------------------------------------------------------------------
  -- GPIO 2 - LED
  -----------------------------------------------------------------------------
  ins_pbi_led1 : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => NB_LED1,
    DATA_OE_INIT     => CST1(NB_LED1-1 downto 0),
    DATA_OE_FORCE    => CST1(NB_LED1-1 downto 0),
    IT_ENABLE        => false
    )
  port map  (
    clk_i            => clk         ,
    cke_i            => '1'         ,
    arstn_i          => arst_b       ,
    pbi_ini_i        => icn_pbi_inis(TARGET_LED1) ,
    pbi_tgt_o        => icn_pbi_tgts(TARGET_LED1) ,
    data_i           => X"00"       ,
    data_o           => led1_o      ,
    data_oe_o        => open        ,
    interrupt_o      => open        ,
    interrupt_ack_i  => '0'
    );

  -----------------------------------------------------------------------------
  -- UART
  -----------------------------------------------------------------------------
  ins_pbi_uart : entity work.pbi_uart(rtl)
    generic map(
      BAUD_RATE      => BAUD_RATE     ,
      CLOCK_FREQ     => CLOCK_FREQ
      )
    port map  (
      clk_i          => clk           ,
      arst_b_i       => arst_b        ,
      pbi_ini_i      => icn_pbi_inis(TARGET_UART)   ,
      pbi_tgt_o      => icn_pbi_tgts(TARGET_UART)   ,
      uart_tx_o      => uart_tx_o     ,
      uart_rx_i      => uart_rx_i     
      );
  
  -----------------------------------------------------------------------------
  -- CPU 1
  -- diff cpu0 vs cpu1
  -----------------------------------------------------------------------------
  gen_cpu1_enable: if CPU1_ENABLE = true
  generate
    -- Lock Step
    ins_pbi_OpenBlaze8_1 : entity work.pbi_OpenBlaze8(rtl)
      port map (
        clk_i            => clk     ,
        cke_i            => '1'     ,
        arstn_i          => arst_b   ,
        iaddr_o          => cpu1_iaddr  ,
        idata_i          => cpu1_idata  ,
        pbi_ini_o        => cpu1_pbi_ini,
        pbi_tgt_i        => cpu_pbi_tgt ,
        interrupt_i      => cpu_it_val  ,
        interrupt_ack_o  => cpu1_it_ack
        );

    diff(0) <= '1' when (   (cpu0_iaddr         /= cpu1_iaddr        )
                         or (cpu0_it_ack        /= cpu1_it_ack       )
                       --or (cpu0_pbi_ini       /= cpu1_pbi_ini      )
                            ) else
               '0';
    
    p_diff_r: process (clk, arst_b) is
    begin  -- process p_diff_r
      if arst_b = '0' then                 -- asynchronous reset (active low)
        diff_r(0) <= '0';
      elsif clk'event and clk = '1' then  -- rising clock edge
        -- Trap 1
        diff_r(0) <= diff_r(0) or diff(0);
      end if;
    end process p_diff_r;

    diff_o(0) <= diff_r(0);
  end generate gen_cpu1_enable;
  
  gen_cpu1_disable: if CPU1_ENABLE = false
  generate
    diff_o(0) <= '0';
  end generate gen_cpu1_disable;

  -----------------------------------------------------------------------------
  -- CPU 2
  -- diff cpu1 vs cpu2
  -- diff cpu2 vs cpu0
  -----------------------------------------------------------------------------
  gen_cpu2_enable: if CPU2_ENABLE = true
  generate
    -- TMR
    ins_pbi_OpenBlaze8_2 : entity work.pbi_OpenBlaze8(rtl)
      port map (
        clk_i            => clk     ,
        cke_i            => '1'     ,
        arstn_i          => arst_b   ,
        iaddr_o          => cpu2_iaddr  ,
        idata_i          => cpu2_idata  ,
        pbi_ini_o        => cpu2_pbi_ini,
        pbi_tgt_i        => cpu_pbi_tgt ,
        interrupt_i      => cpu_it_val  ,
        interrupt_ack_o  => cpu2_it_ack
        );

    diff(1) <= '1' when (   (cpu1_iaddr         /= cpu2_iaddr        )
                         or (cpu1_it_ack        /= cpu2_it_ack       )
                       --or (cpu1_pbi_ini       /= cpu2_pbi_ini      )
                         ) else
               '0';
    diff(2) <= '1' when (   (cpu2_iaddr         /= cpu0_iaddr        )
                         or (cpu2_it_ack        /= cpu0_it_ack       )
                       --or (cpu2_pbi_ini       /= cpu0_pbi_ini      )
                         ) else
               '0';
    
    p_diff_r: process (clk, arst_b) is
    begin  -- process p_diff_r
      if arst_b = '0' then                 -- asynchronous reset (active low)
        diff_r(2 downto 1) <= "00";
      elsif clk'event and clk = '1' then  -- rising clock edge

        -- Trap 1
        diff_r(2 downto 1) <= diff_r(2 downto 1) or diff(2 downto 1);
      end if;
    end process p_diff_r;

    diff_o(2 downto 1) <= diff_r(2 downto 1);
  end generate gen_cpu2_enable;
  
  gen_cpu2_disable: if CPU2_ENABLE = false
  generate
    diff_o(1) <= '0';
    diff_o(2) <= '0';
  end generate gen_cpu2_disable;

  -----------------------------------------------------------------------------
  -- Fault Injection
  -----------------------------------------------------------------------------
  gen_inject_error:   if FAULT_INJECTION = true
  generate
    cpu0_idata(17 downto 1) <= cpu_idata(17 downto 1);
    cpu0_idata(0)           <= cpu_idata(0)  xor inject_error_i(0);

    cpu1_idata(17 downto 1) <= cpu_idata(17 downto 1);
    cpu1_idata(0)           <= cpu_idata(0)  xor inject_error_i(1);

    cpu2_idata(17 downto 1) <= cpu_idata(17 downto 1);
    cpu2_idata(0)           <= cpu_idata(0)  xor inject_error_i(2);
    
  end generate gen_inject_error;

  gen_inject_error_n: if FAULT_INJECTION = false
  generate
    cpu0_idata              <= cpu_idata;
    cpu1_idata              <= cpu_idata;        
    cpu2_idata              <= cpu_idata;        
  end generate gen_inject_error_n;

end architecture rtl;
    
