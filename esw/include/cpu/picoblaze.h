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
// 2026-11-19  1.2      mrosiere Add cpu_nop
// 2026-11-23  1.3      mrosiere Add cpu_hartid (always 0)
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
// Instruction
//--------------------------------------

// No operation : the PicoBlaze has no NOP instruction, LOAD s0, s0 changes nothing
// (macro : inlined, no code when unused)
#define cpu_nop() __asm LOAD s0, s0 __endasm

// Index of the hart : the PicoBlaze has no hart id and runs one cluster
#define cpu_hartid() 0

//--------------------------------------
// Interruption
//--------------------------------------

#define EINT  ENABLE INTERRUPT
#define DINT  DISABLE INTERRUPT

#define interrupt_setup(handler) do { \
    /* In PicoBlaze, the interrupt vector is fixed at address 0. The handler should be placed at this address in the program memory. */ \
} while (0)

void interrupt_enable (void);
void interrupt_disable(void);

#define ISR_FCT void isr (void) __interrupt(1)

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
