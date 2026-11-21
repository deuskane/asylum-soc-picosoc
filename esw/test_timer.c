//-----------------------------------------------------------------------------
// Title      : Integration test of the timer
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_timer.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the sbi_timer of the user SoC, with the testbench (scenario
// test_timer of tb_PicoSoC) on LED0 :
// * reset values and register read back
// * periodic timer (autostart) of TIMER_PERIOD cycles of the SoC clock,
//   interrupt through the user GIC : the interrupt routine counts the
//   periods on LED0, the testbench measures the time between two counts
// * timer stopped after 4 periods : no interrupt any more
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
#define TIMER_PERIOD     2000 // SoC clock cycles (same value in tb_PicoSoC_test_timer_pkg)
#define TIMER_NB_PERIOD  4

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
ISR_FCT
{
  if (gic_isr(GIC) & GIC_TIMER_MSK)
    {
      // One more period on LED0, then acknowledge the timer and the GIC
      gpio_wr(LED0,gpio_rd(LED0)+1);
      gic_clr(TIMER,TIMER_IT_DONE_MSK);
      gic_clr(GIC  ,GIC_TIMER_MSK);
    }
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  gpio_setup(LED0,OUTPUT);
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  // 1. Reset values : counter held in clear (loaded with the initial value
  //    0), not enabled, no event, interrupt masked
  test_check(0x01,PORT_RD(TIMER,TIMER_CONTROL)     == 0x01);
  test_check(0x02,PORT_RD(TIMER,TIMER_TIMER_BYTE0) == 0x00);
  test_check(0x03,PORT_RD(TIMER,TIMER_TIMER_BYTE3) == 0x00);
  test_check(0x04,gic_isr(TIMER) == 0x00);
  test_check(0x05,gic_imr(TIMER) == 0x00);

  // 2. Registers : the 4 bytes of the initial value are read / write
  timer_wr  (TIMER,0x12345678);
  test_check(0x06,PORT_RD(TIMER,TIMER_TIMER_BYTE0) == 0x78);
  test_check(0x07,PORT_RD(TIMER,TIMER_TIMER_BYTE1) == 0x56);
  test_check(0x08,PORT_RD(TIMER,TIMER_TIMER_BYTE2) == 0x34);
  test_check(0x09,PORT_RD(TIMER,TIMER_TIMER_BYTE3) == 0x12);

  // 3. Periodic timer : the counter goes from TIMER_PERIOD-1 down to 0,
  //    then reloads (autostart) : one event every TIMER_PERIOD cycles.
  //    Timer source -> GIC source 2 -> CPU
  timer_wr       (TIMER,TIMER_PERIOD-1);
  gic_clr        (TIMER,TIMER_IT_DONE_MSK);
  gic_it_enable  (TIMER,TIMER_IT_DONE_MSK);
  gic_clr        (GIC  ,GIC_TIMER_MSK);
  gic_it_enable  (GIC  ,GIC_TIMER_MSK);
  interrupt_setup(isr);
  interrupt_enable();
  timer_setup    (TIMER,1,0,1);  // enable, clear released, autostart

  while (gpio_rd(LED0) != TIMER_NB_PERIOD);

  // 4. Timer disabled : no more event (the testbench checks LED0 after PASS)
  timer_setup    (TIMER,0,1,0);
  test_check(0x0A,gpio_rd(LED0) == TIMER_NB_PERIOD);

  test_pass();
}
