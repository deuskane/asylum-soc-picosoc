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

//--------------------------------------
// Port Macro
//--------------------------------------
extern char PBLAZEPORT[];

#define PORT_WR(_ADDR_,_DATA_) PBLAZEPORT[_ADDR_] = _DATA_
#define PORT_RD(_ADDR_)        PBLAZEPORT[_ADDR_]

//--------------------------------------
// Address Map
//--------------------------------------
#define RST                 0x00
#define LED                 0x04
#define IT_VECTOR_MASK      0x08
#define IT_VECTOR           0x0C
		            
#define GPIO_DATA           0x0
#define GPIO_DATA_OE        0x1
#define GPIO_DATA_IN        0x2
#define GPIO_DATA_OUT       0x3

#define VECTOR_MASK_DEFAULT 0x7

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
#ifdef SAFETY_TMR
void isr (void) __interrupt(1)
{
  uint8_t it_vector;

  it_vector = PORT_RD(IT_VECTOR);
  
  if (it_vector == VECTOR_MASK_DEFAULT)
    {
      // Not the first error
      PORT_WR(RST,0);
      PORT_WR(IT_VECTOR_MASK,VECTOR_MASK_DEFAULT);
      PORT_WR(LED,PORT_RD(LED)+1);
      PORT_WR(RST,1);
    }
  else
    {
      // First error
      PORT_WR(IT_VECTOR_MASK,~it_vector);
    }
}

#else

void isr (void) __interrupt(1)
{
  PORT_WR(RST,0);
  PORT_WR(IT_VECTOR_MASK,VECTOR_MASK_DEFAULT);
  PORT_WR(LED,PORT_RD(LED)+1);
  PORT_WR(RST,1);
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
  PORT_WR(RST           +GPIO_DATA_OE,0xFF);
  PORT_WR(LED           +GPIO_DATA_OE,0xFF);
  PORT_WR(IT_VECTOR_MASK+GPIO_DATA_OE,0xFF);
  PORT_WR(IT_VECTOR     +GPIO_DATA_OE,0x00);

  PORT_WR(RST,0);
  PORT_WR(LED,0);

  // Mask Enable
  PORT_WR(IT_VECTOR_MASK,VECTOR_MASK_DEFAULT);

  __asm
    ENABLE INTERRUPT
  __endasm;

  PORT_WR(RST,1);

  //------------------------------------
  // Application Run Loop
  //-----------------------------------_
  while (1);
  //    loop ();
}
