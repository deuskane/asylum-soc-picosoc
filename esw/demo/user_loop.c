//-----------------------------------------------------------------------------
// Title      : UART loop of pseudo random numbers
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : user_loop.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Each iteration of an infinite loop copies the switches to LED0 and prints
// one line on the UART :
//   Loop <loop number> <pseudo random number>\r\n
// both as 8 hexadecimal digits (32 bits). The pseudo random numbers come from
// the xorwow generator of G. Marsaglia ("Xorshift RNGs", 2003) : a xorshift
// on 5 x 32 bits of state plus a Weyl counter (d += 362437). Shifts, xor and
// additions only (RV32I : no multiply). Fixed seed : the same sequence after
// every reset, so a wrong line shows that the CPU went wrong.
// Needs -DHAVE_UART -DCLOCK_FREQ=<Hz> -DBAUD_RATE=<baud>.
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-11-27  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#include <stdint.h>
#include "addrmap_user.h"

//--------------------------------------
// Constant
//--------------------------------------
#define UART_RX_LOOPBACK 0

//--------------------------------------
// State of xorwow : x, y, z, w, v (xorshift) and d (Weyl counter)
//--------------------------------------
typedef struct
{
  uint32_t x, y, z, w, v;
  uint32_t d;
} xorwow_t;

//--------------------------------------
// Interrupt Sub Routine : no interruption used
//--------------------------------------
ISR_FCT
{
}

//--------------------------------------
// xorwow_seed : the seed of Marsaglia
//--------------------------------------
void xorwow_seed(xorwow_t * s)
{
  s->x = 123456789;
  s->y = 362436069;
  s->z = 521288629;
  s->w =  88675123;
  s->v =   5783321;
  s->d =   6615241;
}

//--------------------------------------
// xorwow : next pseudo random number
//--------------------------------------
uint32_t xorwow(xorwow_t * s)
{
  uint32_t t = s->x ^ (s->x >> 2);

  s->x = s->y;
  s->y = s->z;
  s->z = s->w;
  s->w = s->v;
  s->v = (s->v ^ (s->v << 4)) ^ (t ^ (t << 1));
  s->d = s->d + 362437;

  return s->d + s->v;
}

//--------------------------------------
// puthex32 : 32 bits as 8 hexadecimal digits, MSB first
//--------------------------------------
void puthex32(uint32_t value)
{
  puthex((value >> 24) & 0xFF);
  puthex((value >> 16) & 0xFF);
  puthex((value >>  8) & 0xFF);
  puthex((value >>  0) & 0xFF);
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  xorwow_t state;
  uint32_t loop = 0;

  gpio_setup(SWITCH,INPUT);
  gpio_setup(LED0  ,OUTPUT);
  gpio_wr   (LED0  ,0);
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);
  xorwow_seed(&state);

  while (1)
    {
      // LED0 = switches
      gpio_wr(LED0,gpio_rd(SWITCH));

      putchar('L');
      putchar('o');
      putchar('o');
      putchar('p');
      putchar(' ');
      puthex32(loop);
      putchar(' ');
      puthex32(xorwow(&state));
      putchar('\r');
      putchar('\n');

      loop = loop + 1;
    }
}
