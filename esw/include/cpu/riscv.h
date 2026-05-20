//-----------------------------------------------------------------------------
// Title      : Macro for riscv
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : riscv.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-05-17  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#ifndef _riscv_h_
#define _riscv_h_

#include <stdint.h>

//--------------------------------------
// Port Macro
//--------------------------------------
#define DMEM ((volatile uint8_t*)0)

#define PORT_WR(_BA_,_OFFSET_,_DATA_) DMEM[(_BA_)+(_OFFSET_)] = (_DATA_)
#define PORT_RD(_BA_,_OFFSET_)        DMEM[(_BA_)+(_OFFSET_)]

//--------------------------------------
// Interruption
//--------------------------------------

void interrupt_setup(void (*handler)(void));
void interrupt_enable (void);
void interrupt_disable(void);

#define ISR_FCT

#define ISR_RET __asm__ volatile ("mret")

void interrupt_setup(void (*handler)(void))
{
    // Set the trap vector base address register (mtvec) to the handler address
    __asm__ volatile ("csrw mtvec, %0" :: "r"(handler));
    
    // Enable Machine External Interrupts (MEIE) in the mie register (bit 11 = 0x800)
    __asm__ volatile (
        "li t0, 0x800\n"
        "csrs mie, t0"
        : : : "t0"
    );
}

void interrupt_enable(void)
{
   // Set MIE bit (bit 3) in mstatus register
   __asm__ volatile (
       "csrrsi x0, mstatus, 0x8"
   );
}

void interrupt_disable(void)
{
  // Clear MIE bit (bit 3) in mstatus register
  __asm__ volatile (
      "csrrci x0, mstatus, 0x8"
  );
}
#endif
