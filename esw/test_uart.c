//-----------------------------------------------------------------------------
// Title      : Integration test of the UART
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_uart.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the sbi_uart of the user SoC, with the testbench (scenario
// test_uart of tb_PicoSoC) on uart_tx_o / uart_rx_i :
// * reset values (UART disabled, baud rate of the generics) and setup
// * TX : every line of the firmware ; RX polled : the firmware prints '>',
//   the testbench sends 0x5A
// * RX interrupt through the user GIC : the firmware prints '>', the
//   testbench sends 0xA5, the interrupt routine copies it into LED0 and
//   counts the interrupts on LED1
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
#define BAUD_TICK_CNT_MAX ((CLOCK_FREQ/BAUD_RATE)-1)

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
ISR_FCT
{
  if (gic_isr(GIC) & GIC_UART_MSK)
    {
      // Read the byte : the RX FIFO is empty again (level source), then
      // acknowledge the UART and the GIC
      gpio_wr(LED0,getchar());
      gpio_wr(LED1,gpio_rd(LED1)+1);
      gic_clr(UART,UART_IT_RX_EMPTY_B_MSK);
      gic_clr(GIC ,GIC_UART_MSK);
    }
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  uint8_t ctrl_tx,ctrl_rx,imr,baud_lsb,baud_msb;

  // 1. Reset values, read before the setup (no UART to report them yet) :
  //    TX and RX disabled, no interrupt enabled, baud rate counter of the
  //    generics of the SoC (CLOCK_FREQ / BAUD_RATE - 1)
  ctrl_tx  = PORT_RD(UART,UART_CTRL_TX);
  ctrl_rx  = PORT_RD(UART,UART_CTRL_RX);
  imr      = gic_imr(UART);
  baud_lsb = PORT_RD(UART,UART_BAUD_TICK_CNT_MAX_LSB);
  baud_msb = PORT_RD(UART,UART_BAUD_TICK_CNT_MAX_MSB);

  gpio_setup(LED0,OUTPUT);
  gpio_setup(LED1,OUTPUT);
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  test_check(0x01,ctrl_tx  == 0x00);
  test_check(0x02,ctrl_rx  == 0x00);
  test_check(0x03,imr      == 0x00);
  test_check(0x04,baud_lsb == ( BAUD_TICK_CNT_MAX    &0xFF));
  test_check(0x05,baud_msb == ((BAUD_TICK_CNT_MAX>>8)&0xFF));

  // 2. Setup read back : TX and RX enabled, with CTS and RTS
  test_check(0x06,PORT_RD(UART,UART_CTRL_TX) == 0x11);
  test_check(0x07,PORT_RD(UART,UART_CTRL_RX) == 0x11);

  // 3. RX polled : clear the old events, wait for "RX FIFO not empty",
  //    read the byte, then the source is inactive after its clear
  gic_clr(UART,0xFF);
  putchar('>');
  while ((gic_isr(UART) & UART_IT_RX_EMPTY_B_MSK) == 0);
  test_check(0x08,getchar() == 0x5A);
  gic_clr   (UART,UART_IT_RX_EMPTY_B_MSK);
  test_check(0x09,(gic_isr(UART) & UART_IT_RX_EMPTY_B_MSK) == 0);

  // 4. RX interrupt : UART source "RX FIFO not empty" -> GIC source 1 ->
  //    CPU ; the interrupt routine copies the byte into LED0
  gic_it_enable  (UART,UART_IT_RX_EMPTY_B_MSK);
  gic_clr        (GIC ,GIC_UART_MSK);
  gic_it_enable  (GIC ,GIC_UART_MSK);
  interrupt_setup(isr);
  interrupt_enable();
  putchar('>');
  while (gpio_rd(LED1) == 0);
  test_check(0x0A,gpio_rd(LED0) == 0xA5);
  test_check(0x0B,gpio_rd(LED1) == 0x01);

  test_pass();
}
