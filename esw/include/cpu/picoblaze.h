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

#define EINT  ENABLE INTERRUPT
#define DINT  DISABLE INTERRUPT

void enable_interrupt (void);
void disable_interrupt(void);
//inline bool enabled_interrupt();
//void set_interrupt_handler(void *(void))
//void set_interrupt(BOOL enable);

void enable_interrupt(void)
{
   __asm
       EINT
   __endasm;
}

void disable_interrupt(void)
{
  __asm;   
      DINT
  __endasm;
}



// This variable is defined in the picoblaze compiler
extern volatile uint8_t PBLAZEPORT[];

#define PORT_WR(_BA_,_OFFSET_,_DATA_) PBLAZEPORT[(_BA_)+(_OFFSET_)] = (_DATA_)
#define PORT_RD(_BA_,_OFFSET_)        PBLAZEPORT[(_BA_)+(_OFFSET_)]


#endif
