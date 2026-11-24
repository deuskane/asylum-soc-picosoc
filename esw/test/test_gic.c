//-----------------------------------------------------------------------------
// Title      : Integration test of the GIC
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_gic.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the sbi_GIC of the user SoC (cluster 0), with the testbench
// (scenario test_gic of tb_PicoSoC) on it_user_i (GIC source 0). LED0 is
// the request to the testbench (n : send the pulse n), LED1 counts the
// interrupts taken by the CPU :
// * reset values and register read back
// * pulse 1 : source masked, the event is recorded in isr (polling), no
//   interrupt
// * pulse 2 : recorded while masked, then the interrupt is taken as soon
//   as the source is unmasked
// * pulse 3 : source unmasked, interrupt taken at once
// Result on the UART (test.h) : "PASS" or "FAIL <step>"
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-11-21  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#include <stdint.h>
#include "addrmap_user.h"
#include "test.h"

//--------------------------------------
// Constant
//--------------------------------------
#define UART_RX_LOOPBACK 0

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
ISR_FCT
{
  if (gic_isr(GIC) & GIC_IT_USER_MSK)
    {
      gpio_wr(LED1,gpio_rd(LED1)+1);
      gic_clr(GIC,GIC_IT_USER_MSK);
    }
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  gpio_setup(LED0,OUTPUT);
  gpio_setup(LED1,OUTPUT);
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  // 1. Reset values : every source masked, no event (all sources inactive)
  test_check(0x01,gic_imr(GIC) == 0x00);
  test_check(0x02,gic_isr(GIC) == 0x00);

  // 2. Registers : the mask is read / write
  gic_it_enable (GIC,0x1F);
  test_check(0x03,gic_imr(GIC) == 0x1F);
  gic_it_disable(GIC,0x1F);
  test_check(0x04,gic_imr(GIC) == 0x00);

  // The CPU takes the interrupts of the GIC
  interrupt_setup(isr);
  interrupt_enable();

  // 3. Pulse 1, source masked : recorded in isr, no interrupt, cleared by
  //    writing 1
  gpio_wr(LED0,1);
  while ((gic_isr(GIC) & GIC_IT_USER_MSK) == 0);
  test_check(0x05,gpio_rd(LED1) == 0);
  gic_clr   (GIC,GIC_IT_USER_MSK);
  test_check(0x06,gic_isr(GIC) == 0x00);

  // 4. Pulse 2, source masked, then unmasked : the recorded event is taken
  gpio_wr(LED0,2);
  while ((gic_isr(GIC) & GIC_IT_USER_MSK) == 0);
  test_check(0x07,gpio_rd(LED1) == 0);
  gic_it_enable(GIC,GIC_IT_USER_MSK);
  while (gpio_rd(LED1) != 1);
  test_check(0x08,gic_isr(GIC) == 0x00);

  // 5. Pulse 3, source unmasked : interrupt taken at once
  gpio_wr(LED0,3);
  while (gpio_rd(LED1) != 2);
  test_check(0x09,gic_isr(GIC) == 0x00);

  test_pass();
}
