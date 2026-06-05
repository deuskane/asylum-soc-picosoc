-------------------------------------------------------------------------------
-- Title      : PicoSoC
-- Project    : 
-------------------------------------------------------------------------------
-- File       : PicoSoC.vhd
-- Author     : Mathieu Rosiere
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- Copyright (c) 2025
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author   Description
-- 2025-04-14  1.0      mrosiere Created
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library asylum;
use     asylum.uart_pkg.ALL;
use     asylum.ROM_user_pkg.all;
use     asylum.sbi_pkg.all;

package PicoSoC_pkg is

  -----------------------------------------------------------------------------
  -- Address Map
  -----------------------------------------------------------------------------
  constant PICOSOC_USER_ADDR_ENCODING          : string := "binary";
                                               
  constant PICOSOC_USER_SWITCH_BA              : std_logic_vector(8-1 downto 0) := X"00";
  constant PICOSOC_USER_LED0_BA                : std_logic_vector(8-1 downto 0) := X"04";
  constant PICOSOC_USER_LED1_BA                : std_logic_vector(8-1 downto 0) := X"08";
  constant PICOSOC_USER_CRC_BA                 : std_logic_vector(8-1 downto 0) := X"0C";
  constant PICOSOC_USER_SPINLOCK_BA            : std_logic_vector(8-1 downto 0) := X"10";
  constant PICOSOC_USER_MAILBOX_BA             : std_logic_vector(8-1 downto 0) := X"20";
  constant PICOSOC_USER_UART_BA                : std_logic_vector(8-1 downto 0) := X"30";
  constant PICOSOC_USER_SPI_BA                 : std_logic_vector(8-1 downto 0) := X"40";
  constant PICOSOC_USER_GIC_BA                 : std_logic_vector(8-1 downto 0) := X"50";
  constant PICOSOC_USER_TIMER_BA               : std_logic_vector(8-1 downto 0) := X"60";
  constant PICOSOC_USER_RAM_BA                 : std_logic_vector(8-1 downto 0) := X"80";
                                               
  constant PICOSOC_SUPERVISOR_ADDR_ENCODING    : string := "binary";
                                               
  constant PICOSOC_SUPERVISOR_LED0_BA          : std_logic_vector(8-1 downto 0) := X"10";
  constant PICOSOC_SUPERVISOR_LED1_BA          : std_logic_vector(8-1 downto 0) := X"20";
  constant PICOSOC_SUPERVISOR_GIC_BA           : std_logic_vector(8-1 downto 0) := X"40";
  constant PICOSOC_SUPERVISOR_RAM_BA           : std_logic_vector(8-1 downto 0) := X"80";

  -----------------------------------------------------------------------------
  -- GIC Map
  -----------------------------------------------------------------------------
  constant PICOSOC_USER_GIC_IT_USER            : natural  := 0;
  constant PICOSOC_USER_GIC_UART               : natural  := 1;
  constant PICOSOC_USER_GIC_TIMER              : natural  := 2;
  
  constant PICOSOC_SUPERVISOR_GIC_CPU0_VS_CPU1 : natural  := 0;
  constant PICOSOC_SUPERVISOR_GIC_CPU1_VS_CPU2 : natural  := 1;
  constant PICOSOC_SUPERVISOR_GIC_CPU2_VS_CPU0 : natural  := 2;
  
  -----------------------------------------------------------------------------
  -- PicoSoC_user_debug_t
  --
  -- Struct with internal signal of SoC User
  -----------------------------------------------------------------------------

  type PicoSoC_user_debug_t is record
    arst_b      : std_logic;
    cpu_iaddr   : std_logic_vector(ROM_user_ADDR_WIDTH-1 downto 0);
    cpu_idata   : std_logic_vector(ROM_user_DATA_WIDTH-1 downto 0);
                
    cpu_dcs     : std_logic;
    cpu_dre     : std_logic;
    cpu_dwe     : std_logic;
    cpu_daddr   : std_logic_vector( 8-1 downto 0);
    cpu_dready  : std_logic;

    switch_cs   : std_logic;
    switch_ready: std_logic;
    led0_cs     : std_logic;
    led0_ready  : std_logic;
    led1_cs     : std_logic;
    led1_ready  : std_logic;
    uart_cs     : std_logic;
    uart_ready  : std_logic;
    spi_cs      : std_logic;
    spi_ready   : std_logic;

    uart        : uart_debug_t;
    
  end record PicoSoC_user_debug_t;

  -----------------------------------------------------------------------------
  -- PicoSoC_supervisor_debug_t
  --
  -- Struct with internal signal of SoC Supervisor
  -----------------------------------------------------------------------------
  type PicoSoC_supervisor_debug_t is record
    arst_b : std_logic;
  end record PicoSoC_supervisor_debug_t;
  
  -----------------------------------------------------------------------------
  -- Component
  -----------------------------------------------------------------------------
-- [COMPONENT_INSERT][BEGIN]
component PicoSoC_supervisor is
  generic
    (NB_LED0               : positive := 8
    ;NB_LED1               : positive := 8

    ;ICN_ALGO_SEL          : string   := "or"
    ;ICN_MASTER_SEL        : string   := "fix"

    ;NB_CPU                : natural  := 1
    ;CPU_MODEL             : string   := "OpenBlaze8" 
    ;RAM_DEPTH             : natural  := 128
    );
  port
    (clk_i                 : in  std_logic
    ;arst_b_i              : in  std_logic
                          
    ;led0_o                : out std_logic_vector(NB_LED0  -1 downto 0)
    ;led1_o                : out std_logic_vector(NB_LED1  -1 downto 0)
                          
    ;diff_i                : in  std_logic_vector(        3-1 downto 0)
                          
    ;debug_o               : out PicoSoC_supervisor_debug_t
     );
end component PicoSoC_supervisor;

component PicoSoC_top is
  generic
    (FSYS                   : positive := 50_000_000
    ;FSYS_INT               : positive := 50_000_000
    ;BAUD_RATE              : integer  := 115200
    ;UART_DEPTH_TX          : natural  := 0
    ;UART_DEPTH_RX          : natural  := 0
    ;SPI_DEPTH_CMD          : natural  := 0
    ;SPI_DEPTH_TX           : natural  := 0
    ;SPI_DEPTH_RX           : natural  := 0
    ;NB_SWITCH              : positive := 8
    ;NB_LED                 : positive := 19
    ;RESET_POLARITY         : string   := "low"       -- "high" / "low"
    ;SUPERVISOR             : boolean  := True 
    ;SAFETY                 : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;LOCK_STEP_DEPTH        : natural  := 2
    ;FAULT_INJECTION        : boolean  := True  
    ;IT_USER_POLARITY       : string   := "low"       -- "high" / "low"
    ;FAULT_POLARITY         : string   := "low"       -- "high" / "low"
    ;DEBUG_ENABLE           : boolean  := True
    ;CPU_MODEL              : string   := "WardRV"    -- "OpenBlaze8" / "WardRV_fsm"
    ;SUPERVISOR_RAM_DEPTH   : natural  := 128
    ;USER_RAM_DEPTH         : natural  := 128
    ;MAILBOX_FIFO0_DEPTH_TX : natural  := 4
    ;MAILBOX_FIFO0_DEPTH_RX : natural  := 4
    ;MAILBOX_FIFO1_DEPTH_TX : natural  := 4
    ;MAILBOX_FIFO1_DEPTH_RX : natural  := 4    
    );
  port
    (clk_i            : in  std_logic
    ;arst_i           : in  std_logic

    ;switch_i         : in  std_logic_vector(NB_SWITCH-1 downto 0)
    ;led_o            : out std_logic_vector(NB_LED   -1 downto 0)
    ;it_user_i        : in  std_logic

    -- UART Interface
    ;uart_tx_o        : out std_logic
    ;uart_rx_i        : in  std_logic
    ;uart_cts_b_i     : in  std_logic -- Clear   To Send (Active low)
    ;uart_rts_b_o     : out std_logic -- Request To Send (Active low)

    -- SPI Interface
    ;spi_sclk_o       : out std_logic
    ;spi_cs_b_o       : out std_logic
    ;spi_mosi_o       : out std_logic
    ;spi_miso_i       : in  std_logic
     
    -- Error Injection Interface
    ;inject_error_i   : in  std_logic_vector(        3-1 downto 0)

    -- Debug Interface
    ;debug_mux_i      : in  std_logic_vector(        3-1 downto 0)
    ;debug_o          : out std_logic_vector(        8-1 downto 0)
    ;debug_uart_tx_o  : out std_logic
     
    );
end component PicoSoC_top;

component PicoSoC_user is
  generic
    (CLOCK_FREQ             : integer  := 50000000
    ;BAUD_RATE              : integer  := 115200
    ;UART_DEPTH_TX          : natural  := 0
    ;UART_DEPTH_RX          : natural  := 0
    ;SPI_DEPTH_CMD          : natural  := 0
    ;SPI_DEPTH_TX           : natural  := 0
    ;SPI_DEPTH_RX           : natural  := 0
    ;NB_SWITCH              : positive := 8
    ;NB_LED0                : positive := 8
    ;NB_LED1                : positive := 8
    ;SAFETY                 : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;LOCK_STEP_DEPTH        : natural  := 2
    ;FAULT_INJECTION        : boolean  := False
    ;ICN_ALGO_SEL           : string   := "or"
    ;ICN_MASTER_SEL        : string   := "fix"
    ;NB_CPU                 : natural  := 1
    ;CPU_MODEL              : string   := "OpenBlaze8"
    ;RAM_DEPTH              : natural  := 128
    ;MAILBOX_FIFO0_DEPTH_TX : natural  := 4
    ;MAILBOX_FIFO0_DEPTH_RX : natural  := 4
    ;MAILBOX_FIFO1_DEPTH_TX : natural  := 4
    ;MAILBOX_FIFO1_DEPTH_RX : natural  := 4
    );
  port
    (clk_i                 : in  std_logic
    ;arst_b_i              : in  std_logic
                          
    ;switch_i              : in  std_logic_vector(NB_SWITCH-1 downto 0)
    ;led0_o                : out std_logic_vector(NB_LED0  -1 downto 0)
    ;led1_o                : out std_logic_vector(NB_LED1  -1 downto 0)

     -- UART Interface
    ;uart_tx_o             : out std_logic
    ;uart_rx_i             : in  std_logic
    ;uart_cts_b_i          : in  std_logic -- Clear   To Send (Active low)
    ;uart_rts_b_o          : out std_logic -- Request To Send (Active low)
                          
    -- SPI Interface
    ;spi_sclk_o            : out std_logic
    ;spi_cs_b_o            : out std_logic
    ;spi_mosi_o            : out std_logic
    ;spi_miso_i            : in  std_logic
                          
    ;it_i                  : in  std_logic
    ;inject_error_i        : in  std_logic_vector(        3-1 downto 0)
    ;diff_o                : out std_logic_vector(        3-1 downto 0) -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0
                                 
    ;debug_o               : out PicoSoC_user_debug_t
    );
end component PicoSoC_user;

component cpu_safety is
  generic
    (SAFETY                : string   := "lock-step"
    ;LOCK_STEP_DEPTH       : natural  := 2
    ;FAULT_INJECTION       : boolean  := False
    ;CPU_MODEL             : string   := "OpenBlaze8"
    ;IMEM_ADDR_WIDTH       : positive := 12
    ;IMEM_DATA_WIDTH       : positive := 18
    ;DMEM_ADDR_WIDTH       : positive := SBI_ADDR_WIDTH
    ;DMEM_DATA_WIDTH       : positive := SBI_DATA_WIDTH
    );
  port
    (clk_i                 : in  std_logic
    ;cke_i                 : in  std_logic
    ;arst_b_i              : in  std_logic

    -- Instruction Interface
    ;ics_o                 : out std_logic
    ;iaddr_o               : out std_logic_vector(IMEM_ADDR_WIDTH-1 downto 0)
    ;idata_i               : in  std_logic_vector(IMEM_DATA_WIDTH-1 downto 0)

    -- Data 
    ;sbi_ini_o             : out sbi_ini_t
    ;sbi_tgt_i             : in  sbi_tgt_t

    -- Interrupts
    ;interrupt_i           : in  std_logic
    ;interrupt_ack_o       : out std_logic

    -- Error injection and difference output
    ;inject_error_i        : in  std_logic_vector(3-1 downto 0)
    ;diff_o                : out std_logic_vector(3-1 downto 0)
    );
end component cpu_safety;

component cpu_wrapper is
  generic (
    CPU_MODEL        : string   := "OpenBlaze8" 
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
  
end component cpu_wrapper;

-- [COMPONENT_INSERT][END]
end package PicoSoC_pkg;
