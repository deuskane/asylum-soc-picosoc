//-----------------------------------------------------------------------------
// Title      : Integration test of the PWM
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_pwm.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the sbi_PWM of the user SoC, with the testbench (scenario test_pwm
// of tb_PicoSoC) on pwm_o. LED0 gives the step to the testbench, which
// acknowledges each step on the switches :
// * reset values and register read back
// * step 1 : configured but disabled, pwm_o low
// * step 2 : enabled, duty DUTY1 : period and high phase measured
// * step 3 : duty DUTY2 : period and high phase measured
// * step 4 : disabled, pwm_o low
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
// Same values in tb_PicoSoC_test_pwm_pkg
#define UART_RX_LOOPBACK 0
#define PRESCALER        3    // tick of 4 cycles of the SoC clock
#define PERIOD           9    // period of 10 ticks
#define DUTY1            3    // high during 3 ticks
#define DUTY2            7    // high during 7 ticks

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
ISR_FCT
{
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  gpio_setup(LED0,OUTPUT);
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  // 1. Reset values : disabled, generics of sbi_PWM (prescaler 0xC2),
  //    longest period, duty 0
  test_check(0x01,PORT_RD(PWM,PWM_CFG)       == 0x00);
  test_check(0x02,PORT_RD(PWM,PWM_PRESCALER) == 0xC2);
  test_check(0x03,PORT_RD(PWM,PWM_PERIOD)    == 0xFF);
  test_check(0x04,PORT_RD(PWM,PWM_DUTY)      == 0x00);

  // 2. Registers : configuration read back, the PWM stays disabled
  pwm_setup (PWM,PRESCALER,PERIOD,DUTY1);
  test_check(0x05,PORT_RD(PWM,PWM_PRESCALER) == PRESCALER);
  test_check(0x06,PORT_RD(PWM,PWM_PERIOD)    == PERIOD);
  test_check(0x07,PORT_RD(PWM,PWM_DUTY)      == DUTY1);
  gpio_wr   (LED0,1);
  while (gpio_rd(SWITCH) != 1);

  // 3. Enabled : the testbench measures the period and the high phase
  pwm_enable(PWM);
  test_check(0x08,PORT_RD(PWM,PWM_CFG)       == 0x01);
  gpio_wr   (LED0,2);
  while (gpio_rd(SWITCH) != 2);

  // 4. Second duty, taken at the start of the next period
  pwm_duty  (PWM,DUTY2);
  gpio_wr   (LED0,3);
  while (gpio_rd(SWITCH) != 3);

  // 5. Disabled : pwm_o low
  pwm_disable(PWM);
  test_check(0x09,PORT_RD(PWM,PWM_CFG)       == 0x00);
  gpio_wr   (LED0,4);

  test_pass();
}
