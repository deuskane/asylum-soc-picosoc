//-----------------------------------------------------------------------------
// Title      : kcpsm3 file for identity fonction
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : identity.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Read  switch
// Write led
//-----------------------------------------------------------------------------
// Copyright (c) 2021
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2017-03-30  1.0      mrosiere Created
// 2025-01-06  1.0      mrosiere Add comments
//-----------------------------------------------------------------------------
#include <stdint.h>
#include "picoblaze.h"
#include "gpio.h"

//--------------------------------------
// Address Map
//--------------------------------------
#define RST                 0x10
#define LED                 0x20
#define IT_VECTOR_MASK      0x40
#define IT_VECTOR           0x80

#define VECTOR_MASK_DEFAULT 0x7

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
#ifdef SAFETY_TMR
void isr (void) __interrupt(1)
{
  uint8_t it_vector;

  it_vector = gpio_rd(IT_VECTOR);
  
  if (it_vector == VECTOR_MASK_DEFAULT)
    {
      // Not the first error
      gpio_wr(RST,0);
      gpio_wr(IT_VECTOR_MASK,VECTOR_MASK_DEFAULT);
      gpio_wr(LED,gpio_rd(LED)+1);
      gpio_wr(RST,1);
    }
  else
    {
      // First error
      gpio_wr(IT_VECTOR_MASK,~it_vector);
    }
}

#else

void isr (void) __interrupt(1)
{
  gpio_wr(RST,0);
  gpio_wr(IT_VECTOR_MASK,VECTOR_MASK_DEFAULT);
  gpio_wr(LED,gpio_rd(LED)+1);
  gpio_wr(RST,1);
}

#endif

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  //------------------------------------
  // Application Setup
  //------------------------------------
  gpio_setup(RST           ,OUTPUT);
  gpio_setup(LED           ,OUTPUT);
  gpio_setup(IT_VECTOR_MASK,OUTPUT);
  gpio_setup(IT_VECTOR     ,INPUT);

  gpio_wr(RST,0);
  gpio_wr(LED,0);

  // Mask Enable
  gpio_wr(IT_VECTOR_MASK,VECTOR_MASK_DEFAULT);

  __asm
    ENABLE INTERRUPT
  __endasm;

  gpio_wr(RST,1);

  //------------------------------------
  // Application Run Loop
  //-----------------------------------_
  while (1);
  //    loop ();
}
