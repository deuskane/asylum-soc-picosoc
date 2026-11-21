//-----------------------------------------------------------------------------
// Title      : Result of an integration firmware
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// The integration firmwares (esw/test_<ip>.c) print their result on the
// UART, one line read by the testbench (tb_PicoSoC) :
//   "PASS"        every check passed
//   "FAIL <step>" the check <step> (hexa) failed, the firmware stops
// The firmware is built with HAVE_UART (putchar, puthex), sets up the
// UART before its first check and ends with test_pass().
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-11-21  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#ifndef _test_h_
#define _test_h_

#include <stdint.h>

//--------------------------------------
// test_print_fail : print "FAIL <step>"
//--------------------------------------
void test_print_fail(uint8_t step)
{
  putchar('F');
  putchar('A');
  putchar('I');
  putchar('L');
  putchar(' ');
  puthex (step);
  putchar('\r');
  putchar('\n');
}

//--------------------------------------
// test_print_pass : print "PASS"
//--------------------------------------
void test_print_pass(void)
{
  putchar('P');
  putchar('A');
  putchar('S');
  putchar('S');
  putchar('\r');
  putchar('\n');
}

//--------------------------------------
// test_check : the check _STEP_ fails when _COND_ is false, the firmware
//              stops
// test_pass  : every check passed, the firmware stops
// The infinite loops are in the macros, not in the functions : with pbcc,
// a function that ends with an infinite loop breaks the register saves of
// the next function (e.g. the interrupt routine)
//--------------------------------------
#define test_check(_STEP_,_COND_) do { if (!(_COND_)) { test_print_fail(_STEP_); while (1); } } while (0)
#define test_pass()               do { test_print_pass(); while (1); } while (0)

#endif
