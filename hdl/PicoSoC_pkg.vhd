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
-- 2026-10-05  1.1      mrosiere PicoSoC_top component : CPU_MODEL default "OpenBlaze8"
-- 2026-11-16  1.2      mrosiere GIC map : mailbox fifo0 / fifo1 "data available"
-- 2026-11-21  1.3      mrosiere GIC map : switch edges
-- 2026-11-21  1.4      mrosiere PicoSoC_top component : debug_o and
--                               debug_mux_i removed
-- 2026-11-21  1.5      mrosiere Add I2C
-- 2026-11-21  1.6      mrosiere Add PWM
-- 2026-11-21  1.7      mrosiere PicoSoC_user_debug_t : data of the CPU bus
--                               (cpu_dwdata, cpu_drdata), probes of the HWLA
-- 2026-11-22  1.8      mrosiere PicoSoC_top component : uart_rts_b_io
-- 2026-11-22  1.9      mrosiere JTAG : IDCODE and instructions of the
--                               injection / status TAP
-- 2026-11-22  1.10     mrosiere JTAG : IDCODE of the CPU debuggers,
--                               components with the JTAG ports
-- 2026-11-23  1.11     mrosiere PicoSoC_pads component
-- 2026-11-23  1.12     mrosiere PicoSoC_hwla component
-- 2026-11-23  1.13     mrosiere PicoSoC_tap component
-- 2026-11-23  1.14     mrosiere PicoSoC_user_debug_t : cpu_ics (instruction
--                               fetch strobe of the user CPU)
-- 2026-11-23  1.15     mrosiere JTAG over the UART (switches 11) : PicoSoC_pads
--                               and PicoSoC_top components
-------------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

library asylum;
use     asylum.uart_pkg.ALL;
use     asylum.ROM_user_pkg.all;
use     asylum.sbi_pkg.all;
use     asylum.jtag_pkg.all;

package PicoSoC_pkg is

  -----------------------------------------------------------------------------
  -- Address Map
  -----------------------------------------------------------------------------
  constant PICOSOC_USER_ADDR_ENCODING          : string := "binary";
                                               
  constant PICOSOC_USER_GIC_BA                 : std_logic_vector(8-1 downto 0) := X"00";
  constant PICOSOC_USER_SPINLOCK_BA            : std_logic_vector(8-1 downto 0) := X"02";
  constant PICOSOC_USER_SWITCH_BA              : std_logic_vector(8-1 downto 0) := X"04";
  constant PICOSOC_USER_LED0_BA                : std_logic_vector(8-1 downto 0) := X"08";
  constant PICOSOC_USER_LED1_BA                : std_logic_vector(8-1 downto 0) := X"0C";
  constant PICOSOC_USER_CRC_BA                 : std_logic_vector(8-1 downto 0) := X"10";
  constant PICOSOC_USER_MAILBOX_BA             : std_logic_vector(8-1 downto 0) := X"14";
  constant PICOSOC_USER_SPI_BA                 : std_logic_vector(8-1 downto 0) := X"18";
  constant PICOSOC_USER_UART_BA                : std_logic_vector(8-1 downto 0) := X"20";
  constant PICOSOC_USER_TIMER_BA               : std_logic_vector(8-1 downto 0) := X"28";
  constant PICOSOC_USER_I2C_BA                 : std_logic_vector(8-1 downto 0) := X"30";
  constant PICOSOC_USER_PWM_BA                 : std_logic_vector(8-1 downto 0) := X"34";
  constant PICOSOC_USER_RAM2_BA                : std_logic_vector(8-1 downto 0) := X"40";
  constant PICOSOC_USER_RAM1_BA                : std_logic_vector(8-1 downto 0) := X"80";
                                               
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
  constant PICOSOC_USER_GIC_MAILBOX0           : natural  := 3; -- data available in mailbox fifo0
  constant PICOSOC_USER_GIC_MAILBOX1           : natural  := 4; -- data available in mailbox fifo1
  constant PICOSOC_USER_GIC_SWITCH             : natural  := 5; -- edge on a switch
  
  constant PICOSOC_SUPERVISOR_GIC_CPU0_VS_CPU1 : natural  := 0;
  constant PICOSOC_SUPERVISOR_GIC_CPU1_VS_CPU2 : natural  := 1;
  constant PICOSOC_SUPERVISOR_GIC_CPU2_VS_CPU0 : natural  := 2;

  -----------------------------------------------------------------------------
  -- JTAG
  -- IDCODE : version 1, part number, manufacturer 0
  -----------------------------------------------------------------------------
  constant PICOSOC_JTAG_IR_WIDTH               : natural  := 5;
  constant PICOSOC_JTAG_IDCODE_USER_CPU        : std_logic_vector(32-1 downto 0) := x"10001001"; -- debug unit of the user CPU of cluster 0, + i * 0x10000 for cluster i
  constant PICOSOC_JTAG_IDCODE_SUPERVISOR_CPU  : std_logic_vector(32-1 downto 0) := x"10002001"; -- WardRV_debug of the supervisor CPU
  constant PICOSOC_JTAG_IDCODE_INJECT          : std_logic_vector(32-1 downto 0) := x"10003001"; -- injection / status TAP

  -- Instructions of the injection / status TAP
  constant PICOSOC_JTAG_IR_INJECT              : std_logic_vector(PICOSOC_JTAG_IR_WIDTH-1 downto 0) := "00010"; -- jtag_tdr_inout : inject_error (out), diff (in)
  constant PICOSOC_JTAG_IR_STATUS              : std_logic_vector(PICOSOC_JTAG_IR_WIDTH-1 downto 0) := "00011"; -- jtag_tdr_in    : LEDs, switches, resets
  
  -----------------------------------------------------------------------------
  -- PicoSoC_user_debug_t
  --
  -- Struct with internal signal of SoC User
  -----------------------------------------------------------------------------

  type PicoSoC_user_debug_t is record
    arst_b      : std_logic;
    cpu_ics     : std_logic;
    cpu_iaddr   : std_logic_vector(ROM_user_ADDR_WIDTH-1 downto 0);
    cpu_idata   : std_logic_vector(ROM_user_DATA_WIDTH-1 downto 0);
                
    cpu_dcs     : std_logic;
    cpu_dre     : std_logic;
    cpu_dwe     : std_logic;
    cpu_daddr   : std_logic_vector( 8-1 downto 0);
    cpu_dwdata  : std_logic_vector( 8-1 downto 0);
    cpu_drdata  : std_logic_vector( 8-1 downto 0);
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
component PicoSoC_hwla is
  generic
    (FSYS_INT         : positive := 50_000_000 -- Frequency of clk_i (Hz)
    );
  port
    (clk_i            : in  std_logic
    ;arst_b_i         : in  std_logic

    -- Probes (any width) and trigger
    ;probe_i          : in  std_logic_vector
    ;trigger_i        : in  std_logic

    -- Captures : UART 115200 8N1
    ;uart_tx_o        : out std_logic
    );
end component PicoSoC_hwla;

component PicoSoC_pads is
  generic
    (USER_SPI_NB_IO   : natural  := 8          -- SPI data lanes with a pad (up to 8)
    );
  port
    (clk_i            : in    std_logic
    ;arst_b_i         : in    std_logic

    -- Selection of the UART pads : the two MSBs of the switches (asynchronous)
    ;switch_i         : in    std_logic_vector(2-1 downto 0)

    -- Pads : UART / JTAG (FTDI MPSSE AD0 to AD3), SPI, I2C
    ;uart_rx_i        : in    std_logic -- RX   / TCK
    ;uart_tx_io       : inout std_logic -- TX   / TDI
    ;uart_cts_b_io    : inout std_logic -- CTS* / TDO
    ;uart_rts_b_io    : inout std_logic -- RTS* / TMS
    ;spi_sclk_io      : inout std_logic
    ;spi_cs_b_io      : inout std_logic
    ;spi_io_io        : inout std_logic_vector(USER_SPI_NB_IO-1 downto 0)
    ;i2c_scl_io       : inout std_logic
    ;i2c_sda_io       : inout std_logic

    -- User UART
    ;uart_tx_i        : in    std_logic
    ;uart_rx_o        : out   std_logic
    ;uart_cts_b_o     : out   std_logic
    ;uart_rts_b_i     : in    std_logic
    -- HWLA UART (TX only)
    ;debug_uart_tx_i  : in    std_logic
    -- JTAG chain : driven by the JTAG pads (switches 10) or by jtag_bitbang
    -- (switches 11)
    ;jtag_ini_o       : out   jtag_ini_t
    ;jtag_tgt_i       : in    jtag_tgt_t
    -- JTAG over the UART (jtag_bitbang and its UART)
    ;bitbang_tx_i     : in    std_logic
    ;bitbang_rx_o     : out   std_logic
    ;bitbang_jtag_i   : in    jtag_ini_t
    -- SPI (8 data lanes of the SPI)
    ;spi_sclk_i       : in    std_logic
    ;spi_sclk_oe_i    : in    std_logic
    ;spi_cs_b_i       : in    std_logic
    ;spi_cs_b_oe_i    : in    std_logic
    ;spi_io_i         : in    std_logic_vector(8-1 downto 0)
    ;spi_io_oe_i      : in    std_logic_vector(8-1 downto 0)
    ;spi_io_o         : out   std_logic_vector(8-1 downto 0)
    -- I2C (open drain : the output enable pulls the line low)
    ;i2c_scl_i        : in    std_logic
    ;i2c_scl_oe_i     : in    std_logic
    ;i2c_scl_o        : out   std_logic
    ;i2c_sda_i        : in    std_logic
    ;i2c_sda_oe_i     : in    std_logic
    ;i2c_sda_o        : out   std_logic
    );
end component PicoSoC_pads;

component PicoSoC_supervisor is
  generic
    (NB_LED0               : positive := 8
    ;NB_LED1               : positive := 8

    ;ICN_TARGET_SEL        : string   := "or"
    ;ICN_MASTER_SEL        : string   := "fix"

    ;NB_CPU                : natural  := 1
    ;CPU_MODEL             : string   := "OpenBlaze8" 
    ;RAM_DEPTH             : natural  := 128
    ;CPU_DEBUG_ENABLE      : boolean  := False -- Debug unit of the CPU (WardRV_fsm)
    ;IDCODE_VALUE          : std_logic_vector(31 downto 0) := x"10000001" -- IDCODE of its TAP
    );
  port
    (clk_i                 : in  std_logic
    ;arst_b_i              : in  std_logic
                          
    ;led0_o                : out std_logic_vector(NB_LED0  -1 downto 0)
    ;led1_o                : out std_logic_vector(NB_LED1  -1 downto 0)
                          
    ;diff_i                : in  std_logic_vector(        3-1 downto 0)
                          
    ;debug_o               : out PicoSoC_supervisor_debug_t

    -- CPU debug (CPU_DEBUG_ENABLE) : JTAG pins (TDO = TDI without debug unit),
    -- power-on reset of the debug unit, ndmreset
    ;dbg_arst_b_i          : in  std_logic := '1'
    ;jtag_ini_i            : in  jtag_ini_t
    ;jtag_tgt_o            : out jtag_tgt_t
    ;ndmreset_o            : out std_logic
     );
end component PicoSoC_supervisor;

component PicoSoC_tap is
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
end component PicoSoC_tap;

component PicoSoC_top is
  generic
    (FSYS                        : positive := 50_000_000
    ;FSYS_INT                    : positive := 50_000_000
    ;RESET_POLARITY              : string   := "low"       -- "high" / "low"
    ;DEBUG_ENABLE                : boolean  := True        -- HWLA, JTAG TAP of fault injection and status
    ;USER_CPU_DEBUG_ENABLE       : boolean  := False       -- Debug unit of the user CPU of every cluster (cpu_wrapper) : TAPs in the JTAG chain
    ;SUPERVISOR_CPU_DEBUG_ENABLE : boolean  := False       -- Debug unit of the supervisor CPU (cpu_wrapper) : its TAP in the JTAG chain
    ;JTAG_BAUD_RATE              : integer  := 115200      -- JTAG over the UART pads (switches 11) : baud rate of the UART of jtag_bitbang
 
    ;CPU_MODEL                   : string   := "OpenBlaze8" -- "OpenBlaze8" / "WardRV_fsm"

    -- USER SoC
    ;USER_NB_CPU                 : natural  := 1
    ;USER_ICN_TARGET_SEL         : string   := "or"
    ;USER_ICN_MASTER_SEL         : string   := "fix"
    ;USER_RAM1_DEPTH             : natural  := 128         -- Up to 128 bytes
    ;USER_RAM2_DEPTH             : natural  := 64          -- Up to 64  bytes
    ;USER_NB_SWITCH              : positive := 8
    ;USER_NB_LED0                : positive := 8
    ;USER_NB_LED1                : positive := 8
    ;USER_BAUD_RATE              : integer  := 115200
    ;USER_UART_DEPTH_TX          : natural  := 0
    ;USER_UART_DEPTH_RX          : natural  := 0
    ;USER_SPI_DEPTH_CMD          : natural  := 0
    ;USER_SPI_DEPTH_TX           : natural  := 0
    ;USER_SPI_DEPTH_RX           : natural  := 0
    ;USER_SPI_NB_IO              : natural  := 8
    ;USER_SAFETY                 : string   := "lock-step" -- "none" / "lock-step" / "tmr"
    ;USER_LOCK_STEP_DEPTH        : natural  := 2
    ;USER_FAULT_INJECTION        : boolean  := True  
    ;USER_FAULT_POLARITY         : string   := "low"       -- "high" / "low"
    ;USER_IT_POLARITY            : string   := "low"       -- "high" / "low"
    ;USER_MAILBOX_FIFO0_DEPTH_TX : natural  := 4
    ;USER_MAILBOX_FIFO0_DEPTH_RX : natural  := 4
    ;USER_MAILBOX_FIFO1_DEPTH_TX : natural  := 4
    ;USER_MAILBOX_FIFO1_DEPTH_RX : natural  := 4    

    -- SUPERVISOR SoC
    ;SUPERVISOR                  : boolean  := True 
    ;SUPERVISOR_ICN_TARGET_SEL   : string   := "or"
    ;SUPERVISOR_ICN_MASTER_SEL   : string   := "fix"
    ;SUPERVISOR_RAM_DEPTH        : natural  := 128         -- Up to 128 bytes
    );
  port
    (clk_i            : in  std_logic
    ;arst_i           : in  std_logic

    ;switch_i         : in  std_logic_vector(USER_NB_SWITCH-1 downto 0)
    ;led0_o           : out std_logic_vector(USER_NB_LED0  -1 downto 0)
    ;led1_o           : out std_logic_vector(USER_NB_LED1  -1 downto 0)    
    ;led_diff_o       : out std_logic_vector(             3-1 downto 0)
    ;it_user_i        : in  std_logic

    -- UART Interface, shared with the HWLA UART and JTAG (switch_i MSBs) :
    -- UART / JTAG pins of an FTDI MPSSE cable (FT232H, FT2232H)
    ;uart_rx_i        : in    std_logic -- RX   / TCK (FTDI AD0 : TXD  / TCK)
    ;uart_tx_io       : inout std_logic -- TX   / TDI (FTDI AD1 : RXD  / TDI)
    ;uart_cts_b_io    : inout std_logic -- CTS* / TDO (FTDI AD2 : RTS# / TDO), Clear   To Send, active low
    ;uart_rts_b_io    : inout std_logic -- RTS* / TMS (FTDI AD3 : CTS# / TMS), Request To Send, active low

    -- SPI Interface
    ;spi_sclk_io      : inout std_logic
    ;spi_cs_b_io      : inout std_logic
    ;spi_io_io        : inout std_logic_vector(USER_SPI_NB_IO-1 downto 0)

    -- I2C Interface (open drain : external pull-ups)
    ;i2c_scl_io       : inout std_logic
    ;i2c_sda_io       : inout std_logic

    -- PWM Interface
    ;pwm_o            : out std_logic
     
    -- Error Injection Interface
    ;inject_error_i   : in  std_logic_vector(             3-1 downto 0)

    -- Debug Interface
    ;debug_uart_tx_o  : out std_logic -- Captures of the HWLA, UART 115200 8N1 (DEBUG_ENABLE), else 1
     
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
    ;ICN_TARGET_SEL         : string   := "or"
    ;ICN_MASTER_SEL         : string   := "fix"
    ;NB_CPU                 : natural  := 1
    ;CPU_MODEL              : string   := "OpenBlaze8"
    ;RAM1_DEPTH             : natural  := 128
    ;RAM2_DEPTH             : natural  := 64
    ;MAILBOX_FIFO0_DEPTH_TX : natural  := 4
    ;MAILBOX_FIFO0_DEPTH_RX : natural  := 4
    ;MAILBOX_FIFO1_DEPTH_TX : natural  := 4
    ;MAILBOX_FIFO1_DEPTH_RX : natural  := 4
    ;CPU_DEBUG_ENABLE       : boolean  := False -- Debug unit of the CPU of every cluster (WardRV_fsm)
    ;IDCODE_VALUE           : std_logic_vector(31 downto 0) := x"10000001" -- IDCODE of the TAP of cluster 0, + i * 0x10000 for cluster i
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
    ;spi_sclk_oe_o         : out std_logic
    ;spi_cs_b_o            : out std_logic
    ;spi_cs_b_oe_o         : out std_logic
    ;spi_io_o              : out std_logic_vector(        8-1 downto 0)
    ;spi_io_i              : in  std_logic_vector(        8-1 downto 0)
    ;spi_io_oe_o           : out std_logic_vector(        8-1 downto 0)

    -- I2C Interface (open drain : xx_o is 0, xx_oe_o = 1 pulls the line low)
    ;i2c_scl_i             : in  std_logic
    ;i2c_scl_o             : out std_logic
    ;i2c_scl_oe_o          : out std_logic
    ;i2c_sda_i             : in  std_logic
    ;i2c_sda_o             : out std_logic
    ;i2c_sda_oe_o          : out std_logic

    -- PWM Interface
    ;pwm_o                 : out std_logic
                          
    ;it_i                  : in  std_logic
    ;inject_error_i        : in  std_logic_vector(        3-1 downto 0)
    ;diff_o                : out std_logic_vector(        3-1 downto 0) -- bit 0 : cpu0 vs cpu1
                                                                        -- bit 1 : cpu1 vs cpu2
                                                                        -- bit 2 : cpu2 vs cpu0
                                 
    ;debug_o               : out PicoSoC_user_debug_t

    -- CPU debug (CPU_DEBUG_ENABLE) : JTAG chain of the clusters (TDI ->
    -- cluster 0 -> ... -> TDO), power-on reset of the debug units, ndmreset
    ;dbg_arst_b_i          : in  std_logic := '1'
    ;jtag_ini_i            : in  jtag_ini_t
    ;jtag_tgt_o            : out jtag_tgt_t
    ;ndmreset_o            : out std_logic
    );
end component PicoSoC_user;

component cpu_safety is
  generic
    (SAFETY                : string   := "lock-step"
    ;LOCK_STEP_DEPTH       : natural  := 2
    ;FAULT_INJECTION       : boolean  := False
    ;CPU_MODEL             : string   := "OpenBlaze8"
    ;HARTID                : std_logic_vector(31 downto 0) := x"00000000"
    ;DEBUG_ENABLE          : boolean  := False -- WardRV_fsm : debug unit in each copy (cpu_wrapper)
    ;IDCODE_VALUE          : std_logic_vector(31 downto 0) := x"10000001" -- IDCODE of its TAP
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

    -- Debug unit (DEBUG_ENABLE) : JTAG pins, power-on reset of the debug unit,
    -- ndmreset ; without debug unit : TDO = TDI
    ;dbg_arst_b_i          : in  std_logic := '1'
    ;jtag_ini_i            : in  jtag_ini_t
    ;jtag_tgt_o            : out jtag_tgt_t
    ;ndmreset_o            : out std_logic
    );
end component cpu_safety;

component cpu_wrapper is
  generic (
    CPU_MODEL        : string   := "OpenBlaze8"
   ;HARTID           : std_logic_vector(31 downto 0) := x"00000000"
   ;DEBUG_ENABLE     : boolean  := false -- WardRV_fsm only : debug unit WardRV_debug (RISC-V Debug Spec), its TAP
   ;IDCODE_VALUE     : std_logic_vector(31 downto 0) := x"10000001" -- IDCODE of the TAP (DEBUG_ENABLE)
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
    interrupt_ack_o  : out   std_logic;

    -- Debug unit (DEBUG_ENABLE) : JTAG pins, power-on reset of the debug
    -- unit (not the CPU reset), ndmreset (request to reset the CPU and its SoC)
    dbg_arst_b_i     : in    std_logic := '1';
    jtag_ini_i       : in    jtag_ini_t;
    jtag_tgt_o       : out   jtag_tgt_t;
    ndmreset_o       : out   std_logic
    );
  
end component cpu_wrapper;

-- [COMPONENT_INSERT][END]
end package PicoSoC_pkg;
