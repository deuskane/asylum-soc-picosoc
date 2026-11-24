//-----------------------------------------------------------------------------
// Title      : Integration test of the SPI
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_spi.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the sbi_spi of the user SoC and the SPI flash of the testbench
// (scenario test_spi of tb_PicoSoC, flash model m25p40 preloaded with
// sim/mem/memory.mem : 01 02 03 ... at address 0, 0xFF further) :
// * reset values and register read back
// * status register of the flash : write enable latch set by WREN,
//   cleared by WRDI
// * read of the first 4 bytes of the flash
// * page program of 2 bytes at 0x050000, wait for the end of the write,
//   read back
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
#define UART_RX_LOOPBACK    0
#define SPI_WRITE_DISABLE   0x04     // flash instruction WRDI
#define FLASH_SR_WIP        0x01     // flash status register : write in progress
#define FLASH_SR_WEL        0x02     // flash status register : write enable latch
#define FLASH_PAGE          0x050000 // erased page (not in memory.mem)
#define SPI_STATUS_BUSY_MSK 0x40     // SPI status : transfer in progress
#define SPI_STATUS_IDLE     0x04     // SPI status : rx_empty, not busy
#define SPI_STATUS_MASK     0x44     // (the TX and command flags of a FIFO of
                                     // depth 0 follow the master handshake)

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
ISR_FCT
{
}

//--------------------------------------
// flash_status : instruction RDSR, one byte read
//--------------------------------------
uint8_t flash_status(void)
{
  spi_inst(SPI,SPI_READ_SR1,SPI_CONTINUE);
  spi_cmd (SPI,SPI_TX_DISABLE,SPI_RX_ENABLE,SPI_LAST,SPI_CMD_SIZE_SINGLE,1-1);
  return spi_rx(SPI);
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  uint8_t sr;

  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  // 1. Reset values : SPI disabled, prescaler of the generics (0), nothing
  //    received and nothing in progress
  test_check(0x01,PORT_RD(SPI,SPI_CFG)       == 0x00);
  test_check(0x02,PORT_RD(SPI,SPI_PRESCALER) == 0x00);
  test_check(0x03,(PORT_RD(SPI,SPI_STATUS) & SPI_STATUS_MASK) == SPI_STATUS_IDLE);

  // 2. Registers : prescaler read / write (SCLK = clock / 2*(1+1)), SPI
  //    enabled in mode 0 without loopback (MISO from the flash)
  PORT_WR(SPI,SPI_PRESCALER,0x01);
  test_check(0x04,PORT_RD(SPI,SPI_PRESCALER) == 0x01);
  spi_setup(SPI,0,0,SPI_LOOPBACK_DISABLE);
  test_check(0x05,PORT_RD(SPI,SPI_CFG)       == 0x01);

  // 3. Status register of the flash : write enable latch
  test_check(0x06,flash_status() == 0x00);
  spi_inst  (SPI,SPI_WRITE_ENABLE,SPI_LAST);
  test_check(0x07,flash_status() == FLASH_SR_WEL);
  spi_inst  (SPI,SPI_WRITE_DISABLE,SPI_LAST);
  test_check(0x08,flash_status() == 0x00);

  // 4. Read : instruction and 24-bit address, then 4 bytes received
  spi_inst24(SPI,SPI_SINGLE_READ,0x000000,SPI_CONTINUE);
  spi_cmd   (SPI,SPI_TX_DISABLE,SPI_RX_ENABLE,SPI_LAST,SPI_CMD_SIZE_SINGLE,4-1);
  test_check(0x09,spi_rx(SPI) == 0x01);
  test_check(0x0A,spi_rx(SPI) == 0x02);
  test_check(0x0B,spi_rx(SPI) == 0x03);
  test_check(0x0C,spi_rx(SPI) == 0x04);

  // 5. Page program of 2 bytes, poll the status register until the end of
  //    the write (WIP), then read them back
  spi_inst  (SPI,SPI_WRITE_ENABLE,SPI_LAST);
  spi_inst24(SPI,SPI_PAGE_PROGRAM,FLASH_PAGE,SPI_CONTINUE);
  spi_cmd   (SPI,SPI_TX_ENABLE,SPI_RX_DISABLE,SPI_LAST,SPI_CMD_SIZE_SINGLE,2-1);
  spi_tx    (SPI,0x5A);
  spi_tx    (SPI,0xA5);
  do
    {
      sr = flash_status();
    }
  while (sr & FLASH_SR_WIP);
  test_check(0x0D,sr == 0x00);  // WEL cleared at the end of the write

  spi_inst24(SPI,SPI_SINGLE_READ,FLASH_PAGE,SPI_CONTINUE);
  spi_cmd   (SPI,SPI_TX_DISABLE,SPI_RX_ENABLE,SPI_LAST,SPI_CMD_SIZE_SINGLE,2-1);
  test_check(0x0E,spi_rx(SPI) == 0x5A);
  test_check(0x0F,spi_rx(SPI) == 0xA5);

  // 6. End of the last transfer (busy until CS# is released), every byte
  //    received has been read
  while (PORT_RD(SPI,SPI_STATUS) & SPI_STATUS_BUSY_MSK);
  test_check(0x10,(PORT_RD(SPI,SPI_STATUS) & SPI_STATUS_MASK) == SPI_STATUS_IDLE);

  test_pass();
}
