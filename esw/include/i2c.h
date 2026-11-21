//-----------------------------------------------------------------------------
// Title      : Macro for i2c
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : i2c.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// sbi_I2C (asylum:communication:I2C), master and slave :
// * master : for each byte, write its command to cmd, then the byte to
//   data (write) or read it from data (read). This order works with FIFOs
//   of depth 0 : the accesses wait for the I2C transfer
// * slave  : the bytes written by the remote master are read in data, the
//   bytes it reads are written to data (SCL is stretched meanwhile)
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-11-21  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#ifndef _i2c_h_
#define _i2c_h_

#include "I2C_csr.h"

// Commands (cmd : start bit 0, stop bit 1, op bits 3:2)
#define I2C_START_WRITE       (I2C_CMD_START_ENABLE_RAW | I2C_CMD_OP_WRITE_RAW)
#define I2C_START_WRITE_STOP  (I2C_CMD_START_ENABLE_RAW | I2C_CMD_OP_WRITE_RAW | I2C_CMD_STOP_ENABLE_RAW)
#define I2C_WRITE             (I2C_CMD_OP_WRITE_RAW)
#define I2C_WRITE_STOP        (I2C_CMD_OP_WRITE_RAW     | I2C_CMD_STOP_ENABLE_RAW)
#define I2C_READ_ACK          (I2C_CMD_OP_READ_ACK_RAW)
#define I2C_READ_NACK_STOP    (I2C_CMD_OP_READ_NACK_RAW | I2C_CMD_STOP_ENABLE_RAW)

// Address byte of the 7-bit slave address _ADDR_
#define I2C_ADDR_WRITE(_ADDR_) ((_ADDR_)<<1)
#define I2C_ADDR_READ(_ADDR_)  (((_ADDR_)<<1)|1)

// Status bits
#define I2C_STATUS_BUSY_MSK     (1<<I2C_STATUS_BUSY)
#define I2C_STATUS_NACK_MSK     (1<<I2C_STATUS_NACK)
#define I2C_STATUS_BUS_BUSY_MSK (1<<I2C_STATUS_BUS_BUSY)
#define I2C_STATUS_RX_EMPTY_MSK (1<<I2C_STATUS_RX_EMPTY)
#define I2C_STATUS_SLAVE_ADDRESSED_MSK (1<<I2C_STATUS_SLAVE_ADDRESSED)
#define I2C_STATUS_SLAVE_READ_MSK      (1<<I2C_STATUS_SLAVE_READ)

// i2c_setup  : enable the I2C, slave at the 7-bit address _SLAVE_ (0 : no
//              slave)
// i2c_status : status (busy until the end of the last master command,
//              nack, slave addressed, ...)
// i2c_wait   : wait for the end of the master commands
// Master :
// i2c_write  : command _CMD_ with the byte _DATA_ (write commands)
// i2c_read   : command _CMD_ (read commands), then i2c_rd returns the byte
// Slave :
// i2c_rd     : byte written by the remote master
// i2c_wr     : byte read by the remote master
#define i2c_setup(_BA_,_SLAVE_)       PORT_WR(_BA_,I2C_CFG,((_SLAVE_)<<I2C_CFG_SLAVE_ADDR)|(1<<I2C_CFG_ENABLE))
#define i2c_status(_BA_)              PORT_RD(_BA_,I2C_STATUS)
#define i2c_wait(_BA_)                do {} while (i2c_status(_BA_) & I2C_STATUS_BUSY_MSK)
#define i2c_write(_BA_,_CMD_,_DATA_)  do { PORT_WR(_BA_,I2C_CMD,_CMD_); PORT_WR(_BA_,I2C_DATA,_DATA_); } while (0)
#define i2c_read(_BA_,_CMD_)          PORT_WR(_BA_,I2C_CMD,_CMD_)
#define i2c_rd(_BA_)                  PORT_RD(_BA_,I2C_DATA)
#define i2c_wr(_BA_,_DATA_)           PORT_WR(_BA_,I2C_DATA,_DATA_)

#endif
