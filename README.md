This repository incluses the top level of minimal SoC :
- SoC User with 3 controllers GPIO (1 for switch and two for LEDs), 1 UART, 1 MCU based on Xilinx Picoblaze
  - SoC User includes safety features : Lock-Step or TMR.
- SoC Supervisor with 4 controllers GPIO (1 to reset the SoC User, 1 for LEDs, 1 to read error Vector and 1 to mask errors)
  - When an error is detected, the SoC Supervisor reset the SoC User.