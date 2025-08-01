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
#define SWITCH              0x10
#define LED0                0x20

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  gpio_setup(SWITCH,INPUT);
  gpio_setup(LED0  ,OUTPUT);

  while (1)
    {
      uint8_t sw = gpio_rd(SWITCH);

#ifdef INVERT_SWITCH
      sw = ~sw;
#endif
  
      gpio_wr(LED0, sw);
    }
}
