# PicoSoC - Secure System-on-Chip with Safety Features

## Overview

This repository contains a complete System-on-Chip (SoC) implementation featuring a Xilinx Picoblaze-8 microcontroller with integrated safety mechanisms. The architecture consists of two independent SoC domains:

### User SoC Domain
The main application processing domain with:
- **Picoblaze-8 MCU** with instruction ROM and dedicated RAM
- **3 GPIO Controllers** (1 for switches, 2 for LEDs)
- **UART Interface** with CTS/RTS flow control
- **SPI Master Controller** for external device communication
- **Generic Interrupt Controller (GIC)** for MCU interrupt management
- **Interconnect Network (ICN)** for peripheral addressing
- **Timer Module** for timing operations
- **CRC Calculator** for error checking
- **Safety Features**: Lock-Step or Triple Modular Redundancy (TMR) error detection

### Supervisor SoC Domain
An independent safety monitoring domain with:
- **Picoblaze-8 MCU** for supervision logic
- **2 GPIO Controllers** (1 for User SoC reset, 1 for status indication)
- **Generic Interrupt Controller (GIC)** for error signal reception
- **Interconnect Network (ICN)** for peripheral connection
- **Error Detection & Response**: Monitors User SoC health and initiates system reset on fault detection

## Table of Contents

1. [HDL Architecture](#hdl-architecture)
2. [Embedded Software](#embedded-software)
3. [Simulation and Verification](#simulation-and-verification)
4. [Project Structure](#project-structure)

---

## HDL Architecture

The `hdl/` folder contains all VHDL hardware design files that define the System-on-Chip architecture.

### Architecture Hierarchy

```
PicoSoC_top
├── PicoSoC_user (User SoC Domain)
│   ├── Picoblaze-8 Microcontroller
│   ├── 3× GPIO Controllers
│   ├── UART Interface
│   ├── SPI Master
│   ├── GIC (Interrupt Controller)
│   ├── Timer
│   ├── CRC Unit
│   └── ICN (Interconnect)
└── PicoSoC_supervisor (Supervisor SoC Domain)
    ├── Picoblaze-8 Microcontroller
    ├── 2× GPIO Controllers
    ├── GIC (Error Detection)
    └── ICN (Interconnect)
```

### VHDL Entities

#### PicoSoC_top (PicoSoC_top.vhd)

**Purpose:** Top-level entity of the complete SoC system

**Description:** Instantiates and interconnects both the User and Supervisor SoCs. Manages system-wide configuration through generics including clock frequency, UART parameters, FIFO depths, safety mechanisms, and debug features.

**Generics:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `FSYS` | positive | 50_000_000 | System clock frequency (Hz) |
| `FSYS_INT` | positive | 50_000_000 | Internal clock frequency (Hz) |
| `BAUD_RATE` | integer | 115200 | UART baud rate |
| `UART_DEPTH_TX` | natural | 0 | UART TX FIFO depth |
| `UART_DEPTH_RX` | natural | 0 | UART RX FIFO depth |
| `SPI_DEPTH_CMD` | natural | 0 | SPI command FIFO depth |
| `SPI_DEPTH_TX` | natural | 0 | SPI TX FIFO depth |
| `SPI_DEPTH_RX` | natural | 0 | SPI RX FIFO depth |
| `NB_SWITCH` | positive | 8 | Number of input switches |
| `NB_LED` | positive | 19 | Number of output LEDs |
| `RESET_POLARITY` | string | "low" | Reset polarity ("high" or "low") |
| `SUPERVISOR` | boolean | True | Enable supervisor domain |
| `SAFETY` | string | "lock-step" | Safety mode ("none", "lock-step", or "tmr") |
| `FAULT_INJECTION` | boolean | True | Enable fault injection interface |
| `IT_USER_POLARITY` | string | "low" | User interrupt polarity |
| `FAULT_POLARITY` | string | "low" | Fault signal polarity |
| `DEBUG_ENABLE` | boolean | True | Enable debug signals |

**Ports:**

| Name | Mode | Type | Description |
|------|------|------|-------------|
| `clk_i` | in | std_logic | System clock |
| `arst_i` | in | std_logic | Asynchronous reset |
| `switch_i` | in | std_logic_vector(NB_SWITCH-1 downto 0) | Input switches |
| `led_o` | out | std_logic_vector(NB_LED-1 downto 0) | Output LEDs |
| `it_user_i` | in | std_logic | User interrupt input |
| `uart_tx_o` | out | std_logic | UART transmit |
| `uart_rx_i` | in | std_logic | UART receive |
| `uart_cts_b_i` | in | std_logic | UART Clear To Send (active low) |
| `uart_rts_b_o` | out | std_logic | UART Request To Send (active low) |
| `spi_sclk_o` | out | std_logic | SPI serial clock |
| `spi_cs_b_o` | out | std_logic | SPI chip select (active low) |
| `spi_mosi_o` | out | std_logic | SPI Master Out, Slave In |
| `spi_miso_i` | in | std_logic | SPI Master In, Slave Out |
| `inject_error_i` | in | std_logic_vector(2 downto 0) | Fault injection triggers |
| `debug_mux_i` | in | std_logic_vector(2 downto 0) | Debug multiplexer select |
| `debug_o` | out | std_logic_vector(7 downto 0) | Debug output signals |
| `debug_uart_tx_o` | out | std_logic | Debug UART transmit |

---

#### PicoSoC_user (PicoSoC_user.vhd)

**Purpose:** User SoC domain with application logic

**Description:** Main processing unit containing the Picoblaze MCU and all user-facing peripherals. Implements safety features like Lock-Step or Triple Modular Redundancy (TMR) for fault detection and correction.

**Integrated Components:**
- Picoblaze-8 microcontroller (OpenBlaze8) with instruction ROM and dedicated RAM
- 3 GPIO controllers (1 for switches, 2 for LEDs)
- UART interface for serial communication
- SPI Master controller
- Generic Interrupt Controller (GIC)
- Interconnect Network (ICN) for addressing slaves
- Timer module
- CRC calculator for error checking

**Generics:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `CLOCK_FREQ` | integer | 50000000 | Clock frequency (Hz) |
| `BAUD_RATE` | integer | 115200 | UART baud rate |
| `UART_DEPTH_TX` | natural | 0 | UART TX FIFO depth |
| `UART_DEPTH_RX` | natural | 0 | UART RX FIFO depth |
| `SPI_DEPTH_CMD` | natural | 0 | SPI command FIFO depth |
| `SPI_DEPTH_TX` | natural | 0 | SPI TX FIFO depth |
| `SPI_DEPTH_RX` | natural | 0 | SPI RX FIFO depth |
| `NB_SWITCH` | positive | 8 | Number of input switches |
| `NB_LED0` | positive | 8 | Number of LED0 outputs |
| `NB_LED1` | positive | 8 | Number of LED1 outputs |
| `SAFETY` | string | "lock-step" | Safety mode ("none", "lock-step", or "tmr") |
| `FAULT_INJECTION` | boolean | False | Enable fault injection |
| `ICN_ALGO_SEL` | string | "or" | ICN algorithm selection |

**Ports:**

| Name | Mode | Type | Description |
|------|------|------|-------------|
| `clk_i` | in | std_logic | System clock |
| `arst_b_i` | in | std_logic | Asynchronous reset (active low) |
| `switch_i` | in | std_logic_vector(NB_SWITCH-1 downto 0) | Input switches |
| `led0_o` | out | std_logic_vector(NB_LED0-1 downto 0) | LED0 outputs |
| `led1_o` | out | std_logic_vector(NB_LED1-1 downto 0) | LED1 outputs |
| `uart_tx_o` | out | std_logic | UART transmit |
| `uart_rx_i` | in | std_logic | UART receive |
| `uart_cts_b_i` | in | std_logic | UART Clear To Send (active low) |
| `uart_rts_b_o` | out | std_logic | UART Request To Send (active low) |
| `spi_sclk_o` | out | std_logic | SPI serial clock |
| `spi_cs_b_o` | out | std_logic | SPI chip select (active low) |
| `spi_mosi_o` | out | std_logic | SPI Master Out, Slave In |
| `spi_miso_i` | in | std_logic | SPI Master In, Slave Out |
| `it_i` | in | std_logic | Interrupt input |
| `inject_error_i` | in | std_logic_vector(2 downto 0) | Fault injection triggers |
| `diff_o` | out | std_logic_vector(2 downto 0) | Difference outputs (TMR/Lock-Step) |
| `debug_o` | out | PicoSoC_user_debug_t | Debug signals |

---

#### PicoSoC_supervisor (PicoSoC_supervisor.vhd)

**Purpose:** Supervisor SoC domain for safety and error monitoring

**Description:** Independent monitoring unit that oversees the User SoC health. Detects errors reported by the User SoC and initiates corrective actions (system reset). Implements a hardened safety architecture isolated from user logic.

**Integrated Components:**
- Picoblaze-8 microcontroller for supervision logic
- 2 GPIO controllers (1 for User SoC reset control, 1 for status LEDs)
- Generic Interrupt Controller (GIC) for error reception
- Interconnect Network (ICN) for slave connections

**Generics:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `NB_LED0` | positive | 8 | Number of LED0 outputs |
| `NB_LED1` | positive | 8 | Number of LED1 outputs |
| `ICN_ALGO_SEL` | string | "or" | ICN algorithm selection |

**Ports:**

| Name | Mode | Type | Description |
|------|------|------|-------------|
| `clk_i` | in | std_logic | System clock |
| `arst_b_i` | in | std_logic | Asynchronous reset (active low) |
| `led0_o` | out | std_logic_vector(NB_LED0-1 downto 0) | LED0 outputs |
| `led1_o` | out | std_logic_vector(NB_LED1-1 downto 0) | LED1 outputs |
| `diff_i` | in | std_logic_vector(2 downto 0) | Difference inputs (TMR/Lock-Step detection) |
| `debug_o` | out | PicoSoC_supervisor_debug_t | Debug signals |

---

#### PicoSoC_pkg (PicoSoC_pkg.vhd)

**Purpose:** Common package definitions for the SoC

**Description:** Contains shared constants, type definitions, and address mappings used across both User and Supervisor SoCs.

**Key Definitions:**
- Address mappings for all peripherals (GPIO, UART, SPI, GIC, Timer, CRC)
- Address encoding schemes ("binary" for User, "one_hot" for Supervisor)
- Debug signal structures

---

## Embedded Software

The `esw/` folder contains the C and assembly firmware running on the Picoblaze-8 microcontrollers.

### Core Firmware

#### user.c - User SoC Main Application

**Purpose:** Primary firmware for the User SoC domain

**Description:** Main application that manages the Picoblaze-8 microcontroller operations in the User domain. Handles GPIO control for switches and LEDs, UART communication, SPI interface, and interrupt service routines.

**Key Features:**
- GPIO setup and configuration (switches as inputs, LEDs as outputs)
- UART communication with optional loopback support
- SPI communication (with loopback modes for memory testing)
- Interrupt handling through Generic Interrupt Controller (GIC)
- LED control based on interrupt events
- Support for optional SPI memory interface

#### supervisor.c - Supervisor SoC Monitor

**Purpose:** Safety monitoring firmware for the Supervisor domain

**Description:** Lightweight firmware running on the Supervisor Picoblaze-8 that monitors the User SoC health. Implements error detection and response mechanisms. Supports both TMR (Triple Modular Redundancy) and standard modes.

**Key Features:**
- Error detection from User SoC via difference signals
- Interrupt handling for error vectors
- Safety-critical reset mechanism for User SoC
- LED status indication for error conditions
- TMR-aware error counting and reporting

### Application Modules

#### user_identity.c - Simple Identity/Echo Application

**Purpose:** Basic test and demonstration firmware

**Description:** Simple application that reads switch inputs and directly writes them to LED outputs, performing an identity function. Useful for basic testing and verification of GPIO connectivity.

**Key Features:**
- Direct switch-to-LED mapping
- Minimal resource usage
- Ideal for hardware validation

#### user_modbus_rtu.c - Modbus RTU Server

**Purpose:** Modbus RTU protocol implementation

**Description:** Complete Modbus RTU slave implementation for serial communication. Enables the SoC to communicate with Modbus masters over UART, supporting standard register read/write operations.

**Key Features:**
- Full Modbus RTU protocol stack
- Hardware CRC support (CRC_HW option)
- UART loopback testing capability
- Error detection and handling
- Register address mapping
- Support for optional error injection and wait modes

#### user_xmodem.c - XModem File Transfer Protocol

**Purpose:** XModem protocol implementation for firmware updates

**Description:** Implements the XModem protocol for reliable binary file transfer over UART. Allows bootloading or updating application firmware on the SoC.

**Key Features:**
- XModem packet-based protocol
- Start Of Heading (SOH, 0x01) recognition
- End Of Transmission (EOT, 0x04) handling
- Checksum-based integrity verification
- Block-based data transfer
- Interrupt-driven UART communication

### Utility Files

#### dummy.c - Empty Template

**Purpose:** Template for new applications

**Description:** Minimal C file with empty main function, used as a starting template for developing new applications on the Picoblaze-8.

#### user_identity.psm - Picoblaze Assembly Code

**Purpose:** Low-level Picoblaze assembly implementation (optional)

**Description:** Alternative or complementary Picoblaze Macro Assembler code that can be used alongside C code for performance-critical sections or when assembly-level control is needed.

### Include Headers

The `include/` subdirectory contains device driver headers and address map definitions:

| Header | Purpose |
|--------|---------|
| `addrmap_user.h` | User SoC peripheral address mappings and memory layout |
| `addrmap_supervisor.h` | Supervisor SoC peripheral address mappings |
| `uart.h` | UART driver interface |
| `gpio.h` | GPIO controller interface |
| `spi.h` | SPI master controller interface |
| `timer.h` | Timer peripheral interface |
| `gic.h` | Generic Interrupt Controller interface |
| `modbus_rtu.h` | Modbus RTU definitions and functions |
| `crc.h` | CRC calculation utilities |
| `picoblaze.h` | Picoblaze core interface |

---

## Simulation and Verification

The `sim/` folder contains testbenches and simulation scenarios for comprehensive verification of the SoC architecture.

### Simulation Testbenches

#### tb_PicoSoC.vhd - Main SoC Testbench

**Purpose:** Generic testbench for functional verification of PicoSoC configurations

**Description:** Provides comprehensive test environment with stimulus generation for GPIO, UART, SPI, and fault injection interfaces. Supports verification of various safety configurations (none, lock-step, TMR).

**Key Features:**
- Clock and reset generation
- GPIO switch stimulus and LED monitoring
- UART loopback testing
- SPI communication testing
- Fault injection capability
- Support for supervisor and safety mode testing
- Debug signal monitoring

#### tb_PicoSoC_modbus.vhd - Modbus RTU Testbench

**Purpose:** Specialized testbench for Modbus RTU protocol validation

**Description:** Uses UVVM (Universal Verification Methodology) framework with UART VVC (Verification Component) from Bitvis for realistic Modbus protocol testing. Enables comprehensive validation of the Modbus RTU server implementation using UVVM's queue-based command interface.

**Key Features:**
- UVVM-based verification framework
- UART VVC (Verification Component) for protocol-aware stimulus and response checking
- Queue-based command sequencing for flexible test scenarios
- Register read/write operation testing
- Modbus compliance verification
- CRC validation

### Test Scenarios

The `PicoSoC.core` file (FuseSoC format) defines comprehensive test scenarios organized by SoC configuration:

#### Basic Functionality Scenarios

| Scenario | Firmware | Safety | Supervisor | Fault Injection | Watchdog |
|----------|----------|--------|------------|-----------------|----------|
| `sim_soc1_asm_identity` | user_identity.psm | None | No | No | 10k |
| `sim_soc1_c_identity` | user_identity.c | None | No | No | 10k |
| `sim_soc1_c_user` | user.c | None | No | No | 10k |
| `sim_soc1_c_user_uart` | user.c (UART) | None | No | No | 50k |
| `sim_soc1_c_user_uart_spi` | user.c (UART+SPI) | None | No | No | 100k |
| `sim_soc1_c_user_uart_spi_mem` | user.c (SPI memory) | None | No | No | 50k |
| `sim_soc1_c_user_modbus_rtu` | user_modbus_rtu.c | None | No | No | 50k |

#### Lock-Step Safety Scenarios

| Scenario | Firmware | Safety | Supervisor | Fault Injection | Watchdog |
|----------|----------|--------|------------|-----------------|----------|
| `sim_soc2_c_user` | user.c | Lock-Step | No | No | 50k |
| `sim_soc2_c_user_uart` | user.c (UART) | Lock-Step | No | No | 50k |
| `sim_soc3_fault_c_user` | user.c | Lock-Step | Yes | Yes | 50k |

#### TMR (Triple Modular Redundancy) Scenarios

| Scenario | Firmware | Safety | Supervisor | Fault Injection | Watchdog |
|----------|----------|--------|------------|-----------------|----------|
| `sim_soc4_fault_c_user` | user.c | TMR | Yes | Yes | 50k |
| `sim_soc4_fault_c_user_uart` | user.c (UART) | TMR | Yes | No | 50k |

### Hardware Emulation Targets

In addition to simulation, the project provides hardware emulation targets for FPGA boards:

#### Digilent Basys Board
- `emu_basys_asm_identity` - Assembly identity test using ISE toolchain

#### NanoXplore NG-MEDIUM Board
- `emu_ng_medium_c_user` - Full-featured user firmware with supervisor and TMR safety
- `emu_ng_medium_soc1` - Single SoC (no supervisor, no safety)
- `emu_ng_medium_soc1_modbus` - Modbus RTU implementation
- `emu_ng_medium_soc2` - Lock-Step safety without supervisor
- `emu_ng_medium_soc2_fault` - Lock-Step with fault injection
- `emu_ng_medium_soc3_fault` - Lock-Step with supervisor and fault injection
- `emu_ng_medium_soc4_fault` - TMR with supervisor and fault injection

### Waveform Analysis

The `sim/wave/` directory contains GTKWave configuration files:
- `waves.gtkw` - Pre-configured GTKWave settings for signal visualization during simulation

### Verification Coverage

The test plan covers:
1. **Functional Verification**: Basic GPIO, UART, SPI, and Timer operations
2. **Safety Verification**: Lock-Step and TMR error detection mechanisms
3. **Error Injection**: Fault tolerance validation through intentional error injection
4. **Protocol Verification**: Modbus RTU compliance testing
5. **Integration Testing**: Multi-component interaction testing
6. **Edge Cases**: Boundary conditions and error scenarios

---

## Project Structure

```
asylum-soc-picosoc/
├── hdl/
│   ├── PicoSoC_top.vhd        # Top-level SoC entity
│   ├── PicoSoC_user.vhd       # User SoC domain
│   ├── PicoSoC_supervisor.vhd # Supervisor SoC domain
│   └── PicoSoC_pkg.vhd        # Common package definitions
├── esw/
│   ├── user.c                 # User SoC main application
│   ├── supervisor.c           # Supervisor SoC firmware
│   ├── user_identity.c        # Identity test application
│   ├── user_identity.psm      # Picoblaze assembly code
│   ├── user_modbus_rtu.c      # Modbus RTU server
│   ├── user_xmodem.c          # XModem protocol
│   ├── dummy.c                # Empty template
│   └── include/               # Device driver headers
│       ├── addrmap_user.h
│       ├── addrmap_supervisor.h
│       ├── uart.h
│       ├── gpio.h
│       ├── spi.h
│       ├── timer.h
│       ├── gic.h
│       ├── modbus_rtu.h
│       ├── crc.h
│       └── picoblaze.h
├── sim/
│   ├── tb_PicoSoC.vhd         # Main SoC testbench
│   ├── tb_PicoSoC_modbus.vhd  # Modbus RTU testbench
│   └── wave/
│       └── waves.gtkw          # GTKWave configuration
├── boards/                    # Board-specific constraints
│   ├── Digilent-Basys1/
│   │   └── pads.ucf
│   └── NanoXplore-DK625V0/
│       ├── features.py
│       ├── options.py
│       └── pads.py
├── mk/                        # Build system utilities
│   ├── defs.mk
│   └── targets.txt
├── tools/                     # Utility tools
│   ├── addrmap_user.hjson
│   ├── modbus_server_debug.py
│   └── modbus_server.py
├── PicoSoC.core              # FuseSoC configuration
├── Makefile                  # Build automation
└── README.md                 # This file
```

---



