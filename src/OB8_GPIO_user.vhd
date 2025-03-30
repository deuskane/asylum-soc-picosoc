-------------------------------------------------------------------------------
-- Title      : OB8_GPIO
-- Project    : 
-------------------------------------------------------------------------------
-- File       : OB8_GPIO.vhd
-- Author     : Mathieu Rosiere
-- Company    : 
-- Created    : 2017-03-30
-- Last update: 2025-03-30
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
-------------------------------------------------------------------------------


library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library work;
use     work.pbi_pkg.all;

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

  constant CPU1_ENABLE                : boolean := ((SAFETY = "lock-step") or
                                                    (SAFETY = "tmr"));
  constant CPU2_ENABLE                : boolean := ((SAFETY = "tmr"));
  
  constant NB_TARGET                  : positive := 4;
  constant TARGET_SWITCH              : integer := 0;
  constant TARGET_LED0                : integer := 1;
  constant TARGET_LED1                : integer := 2;
  constant TARGET_UART                : integer := 3;
  
  constant TARGET_ID                  : pbi_addrs_t(NB_TARGET-1 downto 0) :=
    ( TARGET_SWITCH => "00000000",
      TARGET_LED0   => "00000100",
      TARGET_LED1   => "00001000",
      TARGET_UART   => "00001100" 
      );

  constant ID_SWITCH                  : std_logic_vector (PBI_ADDR_WIDTH-1 downto 0) := "00000000";
  --                                                                                    "00000011"
  constant ID_LED0                    : std_logic_vector (PBI_ADDR_WIDTH-1 downto 0) := "00000100";
  --                                                                                    "00000011"
  constant ID_LED1                    : std_logic_vector (PBI_ADDR_WIDTH-1 downto 0) := "00001000";
  --                                                                                    "00000011"
  constant ID_UART                    : std_logic_vector (PBI_ADDR_WIDTH-1 downto 0) := "00001100";
  --                                                                                    "00000011"

  constant CST0                       : std_logic_vector (8-1 downto 0) := (others => '0');
  constant CST1                       : std_logic_vector (8-1 downto 0) := (others => '1');

  signal clk                          : std_logic;
  signal arst_b                       : std_logic;
  
  signal rom_addr                     : std_logic_vector(10-1 downto 0);
  signal rom_data                     : std_logic_vector(18-1 downto 0);
  signal iaddr0                       : std_logic_vector(10-1 downto 0);
  signal iaddr1                       : std_logic_vector(10-1 downto 0);
  signal iaddr2                       : std_logic_vector(10-1 downto 0);
  signal idata0                       : std_logic_vector(18-1 downto 0);
  signal idata1                       : std_logic_vector(18-1 downto 0);
  signal idata2                       : std_logic_vector(18-1 downto 0);
  signal pbi_ini                      : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_ini0                     : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_ini1                     : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_ini2                     : pbi_ini_t(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                  wdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_tgt                      : pbi_tgt_t(rdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_tgt_icn                  : pbi_tgt_t(rdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_tgt_switch               : pbi_tgt_t(rdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_tgt_led0                 : pbi_tgt_t(rdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_tgt_led1                 : pbi_tgt_t(rdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_tgt_uart                 : pbi_tgt_t(rdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_inis                     : pbi_inis_t(NB_TARGET-1 downto 0)(addr (PBI_ADDR_WIDTH-1 downto 0),
                                                                         wdata(PBI_DATA_WIDTH-1 downto 0));
  signal pbi_tgts                     : pbi_tgts_t(NB_TARGET-1 downto 0)(rdata(PBI_DATA_WIDTH-1 downto 0));
  signal it_val                       : std_logic;
  signal it_ack                       : std_logic;
  signal it_ack0                      : std_logic;
  signal it_ack1                      : std_logic;
  signal it_ack2                      : std_logic;

  signal diff                         : std_logic_vector(3-1 downto 0); -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0
  signal diff_r                       : std_logic_vector(3-1 downto 0); -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0



begin  -- architecture rtl

  -- Clock & Reset
  clk    <= clk_i;
  arst_b <= arst_b_i;

  ins_it_ctrl : entity work.it_ctrl(rtl)
  port map(
    clk_i    => clk          ,
    arstn_i  => arst_b       ,
    it_i     => it_i         ,
    it_val_o => it_val       ,
    it_ack_i => it_ack
    );
  
  ins_pbi_OpenBlaze8_0 : entity work.pbi_OpenBlaze8(rtl)
  port map (
    clk_i            => clk     ,
    cke_i            => '1'     ,
    arstn_i          => arst_b  ,
    iaddr_o          => iaddr0  ,
    idata_i          => idata0  ,
    pbi_ini_o        => pbi_ini0,
    pbi_tgt_i        => pbi_tgt ,
    interrupt_i      => it_val  ,
    interrupt_ack_o  => it_ack0
    );


  ins_pci_icn : entity work.pci_icn(rtl)
    generic map (
      NB_TARGET         => NB_TARGET,
      TARGET_ID         => TARGET_ID,
      TARGET_ADDR_WIDTH => TARGET_ID
      )
    port map (
      clk_i            => clk        ,
      cke_i            => '1'        ,
      arst_b_i         => arst_b    ,
      pbi_ini_i        => pbi_ini0   ,
      pbi_tgt_o        => pbi_tgt    ,
      pbi_inis_o       => pbi_inis   ,
      pbi_tgts_i       => pbi_tgts
    );

  gen_cpu_vote: if SAFETY = "tmr"
  generate
    rom_addr      <= ((iaddr0   and iaddr1  ) or
                      (iaddr1   and iaddr2  ) or
                      (iaddr2   and iaddr0  ));
    pbi_ini       <= ((pbi_ini0 and pbi_ini1) or
                      (pbi_ini1 and pbi_ini2) or
                      (pbi_ini2 and pbi_ini0));
    it_ack        <= ((it_ack0  and it_ack1 ) or
                      (it_ack1  and it_ack2 ) or
                      (it_ack2  and it_ack0 ));
  end generate;

  gen_cpu_vote_b: if SAFETY /= "tmr"
  generate
    rom_addr      <= iaddr0   ;
    pbi_ini       <= pbi_ini0 ;
    it_ack        <= it_ack0  ;
  end generate;
  
  ins_pbi_OpenBlaze8_ROM : entity work.ROM_user(rom)
    port map (
      clk_i            => clk    ,
      cke_i            => '1'    ,
      address_i        => rom_addr,
      instruction_o    => rom_data
    );
  
  ins_pbi_switch : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => NB_SWITCH,
    DATA_OE_INIT     => CST0(NB_SWITCH-1 downto 0),
    DATA_OE_FORCE    => CST1(NB_SWITCH-1 downto 0),
    IT_ENABLE        => false,
    ID               => ID_SWITCH
    )
  port map  (
    clk_i            => clk           ,
    cke_i            => '1'           ,
    arstn_i          => arst_b         ,
--  pbi_ini_i        => pbi_ini       ,
--  pbi_tgt_o        => pbi_tgt_switch,
    pbi_ini_i        => pbi_inis(TARGET_SWITCH)   ,
    pbi_tgt_o        => pbi_tgts(TARGET_SWITCH)   ,
    data_i           => switch_i      ,
    data_o           => open          ,
    data_oe_o        => open          ,
    interrupt_o      => open          ,
    interrupt_ack_i  => '0'
    );

  ins_pbi_led0 : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => NB_LED0,
    DATA_OE_INIT     => CST1(NB_LED0-1 downto 0),
    DATA_OE_FORCE    => CST1(NB_LED0-1 downto 0),
    IT_ENABLE        => false,
    ID               => ID_LED0
    )
  port map  (
    clk_i            => clk         ,
    cke_i            => '1'         ,
    arstn_i          => arst_b       ,
--  pbi_ini_i        => pbi_ini     ,
--  pbi_tgt_o        => pbi_tgt_led0,
    pbi_ini_i        => pbi_inis(TARGET_LED0) ,
    pbi_tgt_o        => pbi_tgts(TARGET_LED0) ,
    data_i           => X"00"       ,
    data_o           => led0_o      ,
    data_oe_o        => open        ,
    interrupt_o      => open        ,
    interrupt_ack_i  => '0'
    );

  ins_pbi_led1 : entity work.pbi_GPIO(rtl)
    generic map(
    NB_IO            => NB_LED1,
    DATA_OE_INIT     => CST1(NB_LED1-1 downto 0),
    DATA_OE_FORCE    => CST1(NB_LED1-1 downto 0),
    IT_ENABLE        => false,
    ID               => ID_LED1
    )
  port map  (
    clk_i            => clk         ,
    cke_i            => '1'         ,
    arstn_i          => arst_b       ,
--  pbi_ini_i        => pbi_ini     ,
--  pbi_tgt_o        => pbi_tgt_led1,
    pbi_ini_i        => pbi_inis(TARGET_LED1) ,
    pbi_tgt_o        => pbi_tgts(TARGET_LED1) ,
    data_i           => X"00"       ,
    data_o           => led1_o      ,
    data_oe_o        => open        ,
    interrupt_o      => open        ,
    interrupt_ack_i  => '0'
    );

  ins_pbi_uart : entity work.pbi_uart(rtl)
    generic map(
      BAUD_RATE      => BAUD_RATE     ,
      CLOCK_FREQ     => CLOCK_FREQ    ,
      ID             => ID_UART
      )
    port map  (
      clk_i          => clk           ,
      arst_b_i       => arst_b        ,
--    pbi_ini_i      => pbi_ini       ,
--    pbi_tgt_o      => pbi_tgt_uart  ,
      pbi_ini_i      => pbi_inis(TARGET_UART)   ,
      pbi_tgt_o      => pbi_tgts(TARGET_UART)   ,
      uart_tx_o      => uart_tx_o     ,
      uart_rx_i      => uart_rx_i     
      );
  
  gen_cpu1_enable: if CPU1_ENABLE = true
  generate
    -- Lock Step
    ins_pbi_OpenBlaze8_1 : entity work.pbi_OpenBlaze8(rtl)
      port map (
        clk_i            => clk     ,
        cke_i            => '1'     ,
        arstn_i          => arst_b   ,
        iaddr_o          => iaddr1  ,
        idata_i          => idata1  ,
        pbi_ini_o        => pbi_ini1,
        pbi_tgt_i        => pbi_tgt ,
        interrupt_i      => it_val  ,
        interrupt_ack_o  => it_ack1
        );

    diff(0) <= '1' when (   (iaddr0         /= iaddr1        )
                         or (it_ack0        /= it_ack1       )
                       --or (pbi_ini0       /= pbi_ini1      )
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

  gen_cpu2_enable: if CPU2_ENABLE = true
  generate
    -- TMR
    ins_pbi_OpenBlaze8_2 : entity work.pbi_OpenBlaze8(rtl)
      port map (
        clk_i            => clk     ,
        cke_i            => '1'     ,
        arstn_i          => arst_b   ,
        iaddr_o          => iaddr2  ,
        idata_i          => idata2  ,
        pbi_ini_o        => pbi_ini2,
        pbi_tgt_i        => pbi_tgt ,
        interrupt_i      => it_val  ,
        interrupt_ack_o  => it_ack2
        );

    diff(1) <= '1' when (   (iaddr1         /= iaddr2        )
                         or (it_ack1        /= it_ack2       )
                       --or (pbi_ini1       /= pbi_ini2      )
                         ) else
               '0';
    diff(2) <= '1' when (   (iaddr2         /= iaddr0        )
                         or (it_ack2        /= it_ack0       )
                       --or (pbi_ini2       /= pbi_ini0      )
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


  gen_inject_error:   if FAULT_INJECTION = true
  generate
    idata0(17 downto 1) <= rom_data(17 downto 1);
    idata0(0)           <= rom_data(0)  xor inject_error_i(0);

    idata1(17 downto 1) <= rom_data(17 downto 1);
    idata1(0)           <= rom_data(0)  xor inject_error_i(1);

    idata2(17 downto 1) <= rom_data(17 downto 1);
    idata2(0)           <= rom_data(0)  xor inject_error_i(2);
    
  end generate gen_inject_error;

  gen_inject_error_n: if FAULT_INJECTION = false
  generate
    idata0              <= rom_data;
    idata1              <= rom_data;        
    idata2              <= rom_data;        
  end generate gen_inject_error_n;

end architecture rtl;
    
