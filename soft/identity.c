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
#include <intr.h>

//--------------------------------------
// Port Macro
//--------------------------------------
extern char PBLAZEPORT[];

#define PORT_WR(_ADDR_,_DATA_) PBLAZEPORT[_ADDR_] = _DATA_
#define PORT_RD(_ADDR_)        PBLAZEPORT[_ADDR_]

//--------------------------------------
// Address Map
//--------------------------------------
#define SWITCH              0x10
#define LED0                0x20

#define GPIO_DATA           0x0
#define GPIO_DATA_OE        0x1
#define GPIO_DATA_IN        0x2
#define GPIO_DATA_OUT       0x3

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  PORT_WR(SWITCH +GPIO_DATA_OE,0x00);
  PORT_WR(LED0   +GPIO_DATA_OE,0xFF);

  while (1)
    {
      uint8_t sw = PORT_RD(SWITCH);

#ifdef INVERT_SWITCH
      sw = ~sw;
#endif
  
      PORT_WR(LED0, sw);
    }
}
