//-----------------------------------------------------------------------------
// Title      : Integration test of the RAMs and of the address map
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_ram.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the 2 sbi_ram of the user SoC through the interconnects, scenario
// test_ram of tb_PicoSoC :
// * RAM2 (shared, ICN2) : its 64 bytes ; RAM1 (private, ICN1) : its lower
//   96 bytes (the stack of WardRV grows down from the top of RAM1 : 32
//   bytes are left to it, main and ram_test use 16 bytes each)
// * each byte written with its address in the data (an address decoding
//   error reads another byte), then with the complement (every data bit
//   toggles)
// * the unmapped addresses 0x30 to 0x3F are answered by the default slave
//   of ICN2 : a write is ignored, a read returns 0
// WardRV only : pbcc (OpenBlaze8) miscompiles the variable port address
// of PORT_WR(base,i,...) in a loop (the high byte of base+i is used)
// Result on the UART (test.h) : "PASS" or "FAIL <step>"
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-11-21  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#include <stdint.h>
#include "addrmap_user.h"
#include "test.h"

//--------------------------------------
// Constant
//--------------------------------------
#define UART_RX_LOOPBACK 0
#define RAM2_SIZE        64   // bytes tested in RAM2 (all)
#define RAM1_SIZE        96   // bytes tested in RAM1 (not the stack)
#define UNMAPPED_FIRST   0x30 // no target of ICN2 between 0x30 and 0x3F
#define UNMAPPED_LAST    0x3F

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
ISR_FCT
{
}

//--------------------------------------
// ram_test : write size bytes from base with (address ^ pattern), then
// read them all back (the check step fails on the first wrong byte)
//--------------------------------------
void ram_test(uint8_t base,uint8_t size,uint8_t pattern,uint8_t step)
{
  uint8_t i;

  for (i=0; i<size; i++)
    {
      PORT_WR(base,i,i^pattern);
    }
  for (i=0; i<size; i++)
    {
      test_check(step,PORT_RD(base,i) == (i^pattern));
    }
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  uint8_t addr;

  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  // 1. RAM2 then RAM1, address in the data, then its complement
  ram_test(RAM_GLO,RAM2_SIZE,0xA5,0x01);
  ram_test(RAM_LOC,RAM1_SIZE,0x5A,0x02);
  ram_test(RAM_GLO,RAM2_SIZE,0x5A,0x03);
  ram_test(RAM_LOC,RAM1_SIZE,0xA5,0x04);

  // 2. RAM2 still holds its last pattern : RAM1 is another memory
  test_check(0x05,PORT_RD(RAM_GLO,0x3F) == (0x3F^0x5A));

  // 3. Unmapped addresses : default slave
  for (addr=UNMAPPED_FIRST; addr<=UNMAPPED_LAST; addr++)
    {
      PORT_WR(addr,0,0xFF);
      test_check(0x06,PORT_RD(addr,0) == 0x00);
    }

  test_pass();
}
