//-----------------------------------------------------------------------------
// Title      : Integration test of the CRC
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_crc.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the sbi_crc of the user SoC (CRC16, polynomial 0xA001, LSB first :
// the CRC of Modbus RTU), scenario test_crc of tb_PicoSoC :
// * reset value and seed read back
// * CRC of "123456789" (check value of CRC-16/MODBUS : 0x4B37)
// * CRC of a Modbus request, then of the request with its CRC (0x0000)
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

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
ISR_FCT
{
}

//--------------------------------------
// crc_seed : initial value of the CRC register (0xFFFF for Modbus)
//--------------------------------------
void crc_seed(void)
{
  crc_wr(CRC,CRC0,0xFF);
  crc_wr(CRC,CRC1,0xFF);
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  uint8_t i;

  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  // 1. Reset value : CRC register at 0 (no XOR_OUT, no REFLECT_OUT)
  test_check(0x01,crc_rd(CRC,CRC0) == 0x00);
  test_check(0x02,crc_rd(CRC,CRC1) == 0x00);

  // 2. Seed : written in the CRC register, read back unchanged
  crc_seed();
  test_check(0x03,crc_rd(CRC,CRC0) == 0xFF);
  test_check(0x04,crc_rd(CRC,CRC1) == 0xFF);

  // 3. "123456789" : one write of data0 per byte (ASCII 0x31 to 0x39)
  for (i=0x31; i<=0x39; i++)
    {
      crc_wr(CRC,DATA0,i);
    }
  test_check(0x05,crc_rd(CRC,CRC0) == 0x37);
  test_check(0x06,crc_rd(CRC,CRC1) == 0x4B);

  // 4. Modbus request "read 10 holding registers of slave 1" :
  //    01 03 00 00 00 0A, its CRC is sent LSB first : C5 CD
  crc_seed();
  crc_wr(CRC,DATA0,0x01);
  crc_wr(CRC,DATA0,0x03);
  crc_wr(CRC,DATA0,0x00);
  crc_wr(CRC,DATA0,0x00);
  crc_wr(CRC,DATA0,0x00);
  crc_wr(CRC,DATA0,0x0A);
  test_check(0x07,crc_rd(CRC,CRC0) == 0xC5);
  test_check(0x08,crc_rd(CRC,CRC1) == 0xCD);

  // 5. The CRC of a frame followed by its CRC is 0 : the check of a
  //    received Modbus frame
  crc_wr(CRC,DATA0,0xC5);
  crc_wr(CRC,DATA0,0xCD);
  test_check(0x09,crc_rd(CRC,CRC0) == 0x00);
  test_check(0x0A,crc_rd(CRC,CRC1) == 0x00);

  test_pass();
}
