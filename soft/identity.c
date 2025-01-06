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

// External variable using by the sdcc
extern char PBLAZEPORT[];

// Macro to read and write outside the picoblaze
#define PORT_WR(_ADDR_,_DATA_) PBLAZEPORT[_ADDR_] = _DATA_
#define PORT_RD(_ADDR_)        PBLAZEPORT[_ADDR_]

// Register Map
#define LED       0x04
#define SWITCH    0x00

void main()
{
  while (1)
    {
      // Read the switch
      uint8_t sw = PORT_RD(SWITCH);

      // Write switch value into LED
      PORT_WR(LED,sw);
    }

}
