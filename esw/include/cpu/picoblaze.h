//-----------------------------------------------------------------------------
// Title      : Macro for picoblaze
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : picoblaze.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
//-----------------------------------------------------------------------------
// Copyright (c) 2025
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2025-06-14  1.0      mrosiere Created
// 2026-05-14  1.1      mrosiere Support others picoblaze cores 
//                               (but keep the same interface)
//-----------------------------------------------------------------------------

#ifndef _picoblaze_h_
#define _picoblaze_h_

#include <stdint.h>

//--------------------------------------
// Port Macro
//--------------------------------------

// This variable is defined in the picoblaze compiler
extern volatile uint8_t PBLAZEPORT[];

#define PORT_WR(_BA_,_OFFSET_,_DATA_) PBLAZEPORT[(_BA_)+(_OFFSET_)] = (_DATA_)
#define PORT_RD(_BA_,_OFFSET_)        PBLAZEPORT[(_BA_)+(_OFFSET_)]

//--------------------------------------
// Interruption
//--------------------------------------

#define EINT  ENABLE INTERRUPT
#define DINT  DISABLE INTERRUPT

void interrupt_setup(void (*handler)(void));
void interrupt_enable (void);
void interrupt_disable(void);

#define ISR_FCT  __interrupt(1)
#define ISR_RET do {} while (0)

void interrupt_setup(void (*handler)(void))
{
}

void interrupt_enable(void)
{
   __asm
       EINT
   __endasm;
}

void interrupt_disable(void)
{
  __asm;   
      DINT
  __endasm;
}

#endif
