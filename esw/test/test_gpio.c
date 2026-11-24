//-----------------------------------------------------------------------------
// Title      : Integration test of the GPIO (switches, LED0, LED1)
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_gpio.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the 3 sbi_GPIO_irq of the user SoC, with the testbench
// (scenario test_gpio of tb_PicoSoC) on the pins :
// * reset values and register read back
// * LED0 / LED1 pins     : the testbench waits for 0xA5 / 0x5A
// * switch pins          : the testbench sets 0x3C, then 0x00 ; the
//   rising / falling edges are recorded in the isr of SWITCH and reach
//   the CPU through the user GIC (source 5) ; LED0 copies the switches
// Result on the UART (test.h) : "PASS" or "FAIL <step>"
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-11-21  1.0      mrosiere Created
// 2026-11-21  1.1      mrosiere Switch edges by interrupt (user GIC source 5)
//-----------------------------------------------------------------------------

#include <stdint.h>
#include "addrmap_user.h"
#include "test.h"

//--------------------------------------
// Constant
//--------------------------------------
#define UART_RX_LOOPBACK 0

// Switches with an edge, set by the isr : first byte of RAM2 (the local RAM
// of the CPU is kept for its stack)
#define SWITCH_EDGES     RAM_GLO

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
ISR_FCT
{
  if (gic_isr(GIC) & GIC_SWITCH_MSK)
    {
      // Record the edges, then acknowledge the GPIO and the GIC
      PORT_WR(SWITCH_EDGES,0,PORT_RD(SWITCH_EDGES,0) | gic_isr(SWITCH));
      gic_clr(SWITCH,0xFF);
      gic_clr(GIC   ,GIC_SWITCH_MSK);
    }
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  // 1. Reset values : SWITCH is an input, LED0 / LED1 are outputs at 0
  //    (DATA_OE_INIT of PicoSoC_user), edges masked
  //    (isr / imr of the GPIO have the layout of the GIC : macros of gic.h)
  test_check(0x01,PORT_RD(SWITCH,GPIO_IRQ_DATA_OE) == 0x00);
  test_check(0x02,PORT_RD(LED0  ,GPIO_IRQ_DATA_OE) == 0xFF);
  test_check(0x03,PORT_RD(LED1  ,GPIO_IRQ_DATA_OE) == 0xFF);
  test_check(0x04,gpio_rd(LED0)  == 0x00);
  test_check(0x05,gpio_rd(LED1)  == 0x00);
  test_check(0x06,gic_imr(SWITCH) == 0x00);

  // Clear the old events before using the edges (the edge detector of the
  // GPIO has no reset : its input stages are loaded during the reset)
  gic_clr   (SWITCH,0xFF);
  test_check(0x07,gic_isr(SWITCH) == 0x00);

  // 2. Registers : an output reads back its output register, the mask is
  //    read / write
  gpio_wr(LED0,0xA5);
  gpio_wr(LED1,0x5A);
  test_check(0x08,gpio_rd(LED0) == 0xA5);
  test_check(0x09,gpio_rd(LED1) == 0x5A);
  gic_it_enable (SWITCH,0xFF);
  test_check(0x0A,gic_imr(SWITCH) == 0xFF);
  gic_it_disable(SWITCH,0xFF);
  test_check(0x0B,gic_imr(SWITCH) == 0x00);

  // Edges by interrupt : SWITCH it_o is the source 5 of the user GIC
  PORT_WR(SWITCH_EDGES,0,0);
  gic_it_enable  (SWITCH,0xFF);
  gic_clr        (GIC   ,GIC_SWITCH_MSK);
  gic_it_enable  (GIC   ,GIC_SWITCH_MSK);
  interrupt_setup(isr);
  interrupt_enable();

  // 3. Rising edges : the testbench sees LED0 = 0xA5 and LED1 = 0x5A on the
  //    pins, then sets the switches to 0x3C. Each rising edge sets its isr
  //    bit (IRQ_POSEDGE) and interrupts the CPU, the isr clears it
  while (PORT_RD(SWITCH_EDGES,0) != 0x3C);
  test_check(0x0C,gpio_rd(SWITCH) == 0x3C);
  test_check(0x0D,gic_isr(SWITCH) == 0x00);

  // 4. Falling edges : LED0 copies the switches (0x3C on the pins), then the
  //    testbench clears them (IRQ_NEGEDGE)
  PORT_WR(SWITCH_EDGES,0,0);
  gpio_wr(LED0,gpio_rd(SWITCH));
  while (PORT_RD(SWITCH_EDGES,0) != 0x3C);
  test_check(0x0E,gpio_rd(SWITCH) == 0x00);

  // 5. Direction : LED1 as input reads its pin data_i (tied to 0 in
  //    PicoSoC_user), not its output register 0x5A
  gpio_setup(LED1,INPUT);
  test_check(0x0F,gpio_rd(LED1) == 0x00);
  gpio_setup(LED1,OUTPUT);
  test_check(0x10,gpio_rd(LED1) == 0x5A);

  test_pass();
}
