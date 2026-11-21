//-----------------------------------------------------------------------------
// Title      : Integration test of the I2C
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : test_i2c.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Drives the sbi_I2C of the user SoC, master and slave, with the testbench
// (scenario test_i2c of tb_PicoSoC : UVVM I2C BFM, pull-ups on SCL and SDA) :
// * reset values (I2C disabled, prescaler for 100 kHz) and register read
//   back
// * master : write of 2 bytes to the BFM slave at I2C_SLAVE, read back of
//   the 2 bytes (the BFM returns what it received), write to an address
//   without slave : not acknowledged (NACK)
// * slave at I2C_ME : once LED0 = 1, the BFM master writes 2 bytes, then
//   reads them back. The firmware serves the slave by polling the status
//   (no interrupt) ; SCL is stretched until each byte is read / written.
//   The testbench acknowledges the end of its read on the switches
// Result on the UART (test.h) : "PASS" or "FAIL <step>"
// pbcc (OpenBlaze8) saves a register at its first use in main : no local
// variable, and a status bit is tested before the first polling loop, so
// that no register is saved inside a loop (the stack would overflow)
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
// Same values in tb_PicoSoC_test_i2c_pkg
#define UART_RX_LOOPBACK 0
#define I2C_SLAVE        0x50 // BFM slave
#define I2C_NO_SLAVE     0x51 // no slave at this address
#define I2C_ME           0x3A // slave of the SoC
#define I2C_100KHZ       ((uint8_t)(CLOCK_FREQ/400000-1)) // prescaler : a quarter of the SCL period
#define MASTER_DATA0     0xA5 // bytes written by the master of the SoC
#define MASTER_DATA1     0x5A
#define SLAVE_DATA0      0x3C // bytes written by the BFM master
#define SLAVE_DATA1      0xC3
#define SLAVE_READ       (I2C_STATUS_SLAVE_ADDRESSED_MSK|I2C_STATUS_SLAVE_READ_MSK)

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
ISR_FCT
{
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  gpio_setup(LED0,OUTPUT);
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);

  // 1. Reset values : I2C disabled, SCL at 100 kHz, nothing in progress
  test_check(0x01,PORT_RD(I2C,I2C_CFG)       == 0x00);
  test_check(0x02,PORT_RD(I2C,I2C_PRESCALER) == I2C_100KHZ);
  test_check(0x03,i2c_status(I2C)            == I2C_STATUS_RX_EMPTY_MSK);

  // 2. Registers : prescaler read / write (then back to 100 kHz), I2C
  //    enabled with the slave address ; the bus is free (pull-ups)
  PORT_WR(I2C,I2C_PRESCALER,0x55);
  test_check(0x04,PORT_RD(I2C,I2C_PRESCALER) == 0x55);
  PORT_WR(I2C,I2C_PRESCALER,I2C_100KHZ);
  i2c_setup (I2C,I2C_ME);
  test_check(0x05,PORT_RD(I2C,I2C_CFG)       == ((I2C_ME<<1)|1));
  test_check(0x06,(i2c_status(I2C) & I2C_STATUS_BUS_BUSY_MSK) == 0);

  // 3. Master write : START, address + W, 2 bytes, STOP ; every byte
  //    acknowledged, the bus is free after the STOP
  i2c_write (I2C,I2C_START_WRITE,I2C_ADDR_WRITE(I2C_SLAVE));
  i2c_write (I2C,I2C_WRITE      ,MASTER_DATA0);
  i2c_write (I2C,I2C_WRITE_STOP ,MASTER_DATA1);
  i2c_wait  (I2C);
  test_check(0x07,(i2c_status(I2C) & (I2C_STATUS_NACK_MSK|I2C_STATUS_BUS_BUSY_MSK)) == 0);

  // 4. Master read back : START, address + R, 2 bytes (ACK, then NACK on
  //    the last one), STOP
  i2c_write (I2C,I2C_START_WRITE,I2C_ADDR_READ(I2C_SLAVE));
  i2c_read  (I2C,I2C_READ_ACK);
  test_check(0x08,i2c_rd(I2C) == MASTER_DATA0);
  i2c_read  (I2C,I2C_READ_NACK_STOP);
  test_check(0x09,i2c_rd(I2C) == MASTER_DATA1);
  i2c_wait  (I2C);
  test_check(0x0A,(i2c_status(I2C) & (I2C_STATUS_NACK_MSK|I2C_STATUS_BUS_BUSY_MSK)) == 0);

  // 5. Master, wrong address : no slave answers, NACK
  i2c_write (I2C,I2C_START_WRITE_STOP,I2C_ADDR_WRITE(I2C_NO_SLAVE));
  i2c_wait  (I2C);
  test_check(0x0B,(i2c_status(I2C) & (I2C_STATUS_NACK_MSK|I2C_STATUS_BUS_BUSY_MSK)) == I2C_STATUS_NACK_MSK);

  // 6. Slave, the BFM master writes 2 bytes : read each one as soon as it
  //    is received (checked at once : no variable, see the pbcc note above)
  gpio_wr   (LED0,1);
  while (i2c_status(I2C) & I2C_STATUS_RX_EMPTY_MSK);
  test_check(0x0C,i2c_rd(I2C) == SLAVE_DATA0);
  while (i2c_status(I2C) & I2C_STATUS_RX_EMPTY_MSK);
  test_check(0x0D,i2c_rd(I2C) == SLAVE_DATA1);

  // 7. Slave, the BFM master reads 2 bytes : addressed in read, send back
  //    the 2 bytes received
  while ((i2c_status(I2C) & SLAVE_READ) != SLAVE_READ);
  i2c_wr    (I2C,SLAVE_DATA0);
  i2c_wr    (I2C,SLAVE_DATA1);

  // 8. End of the read (NACK of the BFM master on the last byte, STOP),
  //    acknowledged by the testbench : the bus is free
  while (gpio_rd(SWITCH) != 1);
  test_check(0x0E,(i2c_status(I2C) & I2C_STATUS_BUS_BUSY_MSK) == 0);

  test_pass();
}
