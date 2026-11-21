//-----------------------------------------------------------------------------
// Title      : Integration test of the mailbox (2 CPUs)
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_mailbox.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the sbi_mailbox of the user SoC from 2 CPU clusters (USER_NB_CPU
// = 2, same ROM), scenario test_mailbox of tb_PicoSoC. The first CPU that
// takes the spinlock lock 1 is the requester, the other one the responder :
// * requester : reset values, FIFO order and full / empty flags of fifo1
// * 4 requests : the requester writes a byte in fifo0 ; the "data
//   available" source of fifo0 interrupts the responder (GIC of its
//   cluster), which answers byte ^ 0xFF in fifo1 ; the source of fifo1
//   interrupts the requester, which shows the answer on LED0 and counts
//   the answers on LED1
// Result on the UART, printed by the requester (test.h) : "PASS" or
// "FAIL <step>"
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
#define UART_RX_LOOPBACK  0
#define MAILBOX_EMPTY     0x01 // status : no data to read
#define MAILBOX_FULL      0x02 // status : no free slot
#define MAILBOX_DEPTH     8    // bytes in a channel (DEPTH_TX + DEPTH_RX of PicoSoC_user)
#define NB_REQUEST        4

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------

// Responder : answer the request of fifo0 in fifo1. The source is a level :
// read the channel before clearing it in the GIC
void mailbox0_it(void)
{
  mailbox_push(MAILBOX,1,mailbox_pop(MAILBOX,0)^0xFF);
  gic_clr     (GIC,GIC_MAILBOX0_MSK);
}

// Requester : answer on LED0, one more answer on LED1
void mailbox1_it(void)
{
  gpio_wr(LED0,mailbox_pop(MAILBOX,1));
  gpio_wr(LED1,gpio_rd(LED1)+1);
  gic_clr(GIC,GIC_MAILBOX1_MSK);
}

ISR_FCT
{
  // The GIC also records the masked sources : serve the enabled ones only
  uint8_t it = gic_isr(GIC) & gic_imr(GIC);

  if (it & GIC_MAILBOX0_MSK)
    {
      mailbox0_it();
    }
  if (it & GIC_MAILBOX1_MSK)
    {
      mailbox1_it();
    }
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  uint8_t i;

  // Role of the CPU : the first one to take the lock 1 is the requester
  if (spinlock_try_lock(SPINLOCK,1) != 0)
    {
      // Responder : interrupted by the "data available" source of fifo0
      gic_clr        (GIC,GIC_MAILBOX0_MSK);
      gic_it_enable  (GIC,GIC_MAILBOX0_MSK);
      interrupt_setup(isr);
      interrupt_enable();
      while (1);
    }

  // Requester : checks and result
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  // 1. Reset values : both channels empty
  test_check(0x01,PORT_RD(MAILBOX,MAILBOX_STATUS0) == MAILBOX_EMPTY);
  test_check(0x02,PORT_RD(MAILBOX,MAILBOX_STATUS1) == MAILBOX_EMPTY);

  // 2. fifo1 alone (the responder does not read it) : full after
  //    MAILBOX_DEPTH bytes, read back in order, then empty
  for (i=0; i<MAILBOX_DEPTH; i++)
    {
      mailbox_push(MAILBOX,1,i);
    }
  test_check(0x03,PORT_RD(MAILBOX,MAILBOX_STATUS1) == MAILBOX_FULL);
  for (i=0; i<MAILBOX_DEPTH; i++)
    {
      test_check(0x04,mailbox_pop(MAILBOX,1) == i);
    }
  test_check(0x05,PORT_RD(MAILBOX,MAILBOX_STATUS1) == MAILBOX_EMPTY);

  // 3. Requests : interrupted by the "data available" source of fifo1
  //    (cleared first : step 2 has set it)
  gic_clr        (GIC,GIC_MAILBOX1_MSK);
  gic_it_enable  (GIC,GIC_MAILBOX1_MSK);
  interrupt_setup(isr);
  interrupt_enable();
  for (i=1; i<=NB_REQUEST; i++)
    {
      mailbox_push(MAILBOX,0,i*0x11);
      while (gpio_rd(LED1) != i);
      test_check(0x06,gpio_rd(LED0) == ((i*0x11)^0xFF));
    }

  test_pass();
}
