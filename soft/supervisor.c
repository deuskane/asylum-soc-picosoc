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
// 2025-01-06  1.1      mrosiere Add comments
// 2025-07-05  1.2      mrosiere Use GIC instead GPIO
//-----------------------------------------------------------------------------
#include <stdint.h>
#include "picoblaze.h"
#include "gpio.h"
#include "gic.h"

//--------------------------------------
// Address Map
//--------------------------------------
#define RST                 0x10
#define LED                 0x20
#define GIC                 0x80

#define VECTOR_MASK_DEFAULT 0x7

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
#ifdef SAFETY_TMR
void isr (void) __interrupt(1)
{
  uint8_t it_vector;

  it_vector = gic_get(GIC);
  
  if (gic_ism(GIC) == VECTOR_MASK_DEFAULT)
    {
      // First error
      gic_it_disable(GIC,it_vector);
      gic_clr       (GIC,it_vector);
    }
  else
    {
      // Not the first error
      gpio_wr       (RST,0);
      gic_clr       (GIC,it_vector);
      gic_it_enable (GIC,VECTOR_MASK_DEFAULT);
      gpio_wr       (LED,gpio_rd(LED)+1);
      gpio_wr       (RST,1);
    }
}

#else

void isr (void) __interrupt(1)
{
  gpio_wr       (RST,0);
  gic_clr       (GIC,VECTOR_MASK_DEFAULT);
  gic_it_enable (GIC,VECTOR_MASK_DEFAULT);
  gpio_wr       (LED,gpio_rd(LED)+1);
  gpio_wr       (RST,1);
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
  gpio_setup    (RST           ,OUTPUT);
  gpio_setup    (LED           ,OUTPUT);

  gpio_wr       (RST,0);
  gpio_wr       (LED,0);

  // Mask Enable
  gic_it_enable (GIC,VECTOR_MASK_DEFAULT);

  __asm
    ENABLE INTERRUPT
  __endasm;

  gpio_wr       (RST,1);

  //------------------------------------
  // Application Run Loop
  //-----------------------------------_
  while (1);
  //    loop ();
}
