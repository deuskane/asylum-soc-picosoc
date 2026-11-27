//-----------------------------------------------------------------------------
// Title      : Integration test of the spinlock
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_spinlock.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the sbi_spinlock of the user SoC from one CPU, scenario
// test_spinlock of tb_PicoSoC (the locks shared by several CPUs : see
// esw/demo/user_hello.c on the branch main) :
// * a read takes a free lock (returns 0) and returns non 0 while taken
// * the 2 locks are independent
// * a write of 0 releases a lock, a write never takes it
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
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  // 1. Lock 0 free after the reset : the first read takes it, the next
  //    reads see it taken
  test_check(0x01,spinlock_try_lock(SPINLOCK,0) == 0x00);
  test_check(0x02,spinlock_try_lock(SPINLOCK,0) != 0x00);
  test_check(0x03,spinlock_try_lock(SPINLOCK,0) != 0x00);

  // 2. Lock 1 is independent : still free while lock 0 is taken
  test_check(0x04,spinlock_try_lock(SPINLOCK,1) == 0x00);
  test_check(0x05,spinlock_try_lock(SPINLOCK,1) != 0x00);

  // 3. Release of lock 0 : free again, lock 1 still taken
  spinlock_unlock(SPINLOCK,0);
  test_check(0x06,spinlock_try_lock(SPINLOCK,0) == 0x00);
  test_check(0x07,spinlock_try_lock(SPINLOCK,1) != 0x00);

  // 4. A write never takes a lock : lock 1 released, then written with
  //    0xFF, is still free (and taken by this read)
  spinlock_unlock(SPINLOCK,1);
  PORT_WR(SPINLOCK,SPINLOCK_LOCK1,0xFF);
  test_check(0x08,spinlock_try_lock(SPINLOCK,1) == 0x00);
  test_check(0x09,spinlock_try_lock(SPINLOCK,1) != 0x00);

  test_pass();
}
