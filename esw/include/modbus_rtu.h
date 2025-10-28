//-----------------------------------------------------------------------------
// Title      : Macro to define Address Map for user soc
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : modbus_rtu.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
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

#define MODBUS_ADDRESS                  0x01

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







