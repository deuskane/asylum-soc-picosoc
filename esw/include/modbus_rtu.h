//-----------------------------------------------------------------------------
// Title      : Constants of the Modbus RTU protocol
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : modbus_rtu.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Constants of the Modbus RTU server (user_modbus_rtu.c) : slave address,
// function codes and exception codes
//-----------------------------------------------------------------------------
// Copyright (c) 2025
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2025-10-18  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#ifndef _MODBUS_RTU_H_
#define _MODBUS_RTU_H_

#include <stdint.h>

#define MODBUS_ADDRESS                  0x5A

// Modbus function codes
typedef enum
  {
   MODBUS_FC_READ_HOLDING_REGISTERS    = 0x03,
   MODBUS_FC_WRITE_SINGLE_REGISTER     = 0x06
  } ModbusFunctionCode;

// Modbus Error codes
typedef enum
  {
   MODBUS_ERR_INVALID_FUNC = 0x01,
   MODBUS_ERR_INVALID_ADDR = 0x02,
   MODBUS_ERR_INVALID_DATA = 0x03
  } ModbusErrorCode;

#endif // MODBUS_H







