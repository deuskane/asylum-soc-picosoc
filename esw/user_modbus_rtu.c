//-----------------------------------------------------------------------------
// Title      : Macro to define Address Map for user soc
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : user_modbus_rtu.c
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

#include <intr.h>
#include "addrmap_user.h"
#include "modbus_rtu.h"

// CRC calculation
static uint16_t crc16_init()
{
  return 0xFFFF;
}

static uint16_t crc16_next(uint16_t crc,
			   uint8_t  data)
{
  crc = crc ^ data;

  for (uint8_t i = 8; i != 0; i--)
    {
      if ((crc & 0x0001) != 0)
	{
	  crc >>= 1;
	  crc ^= 0xA001;
	}
      else
	{
	  crc >>= 1;
	}
    }

  return crc;
}

uint16_t modbus_response (uint16_t crc,
			  uint8_t  byte
			  )
{
  putchar(byte);
  return crc16_next(crc,byte);
}

void modbus_response_crc (uint16_t crc)
{
  uint8_t byte;

  byte = crc & 0xFF;
  putchar(byte); // CRC : send LSB first

  byte = (crc >> 16)&0xFF;
  putchar(byte);
}

void modbus_request(uint8_t *request, uint16_t length)
{
  if (length < 8) return;
  
  uint8_t  slave_id      = request[0];
  uint8_t  function_code = request[1];

  // Check Slave ID
  if (slave_id != MODBUS_ADDRESS) return;

  uint16_t crc       = crc16_init();

  switch (function_code)
    {
    case MODBUS_FC_READ_HOLDING_REGISTERS:
      // Read Holding Registers
      // Request must be 8 bytes
      // Respons must be 5+2*N bytes
      
      // Modbus uses 16b address and 16b data
      // here -> ignore MSB

      //uint16_t read_addr = (request[2] << 8) | request[3];
      //uint16_t read_len  = (request[4] << 8) | request[5];
      uint8_t  read_addr = request[3]; // ignore MSB : request[2]
      uint8_t  read_len  = request[5]; // ignore MSB : request[4]

      // Response :
      // Byte 0 : Slave ID
      // Byte 1 : Function Code
      // Byte 2 : Number of read bytes
      crc = modbus_response(crc,slave_id     );
      crc = modbus_response(crc,function_code);
      crc = modbus_response(crc,read_len << 1); // read_len is in read word so 16b

      // Byte 3 : read data MSB
      // Byte 4 : read data LSB
      for (int i = 0; i < read_len; i++)
	{
	  //uint16_t read_data = holding_registers[read_addr + i];
	  //crc = modbus_response(crc,(read_data >> 8  ));
	  //crc = modbus_response(crc,(read_data & 0xFF));

	  uint8_t read_data = PORT_RD(0,read_addr);
	  crc = modbus_response(crc,0x00);
	  crc = modbus_response(crc,read_data);
	  read_addr ++;
	}
      
      break;
      
    case MODBUS_FC_WRITE_SINGLE_REGISTER:
      // Write Single Register

      // Modbus uses 16b address and 16b data
      // here -> ignore MSB
      uint8_t  write_addr = request[3]; // ignore MSB : request[2]
      uint8_t  write_data = request[5]; // ignore MSB : request[4]

      PORT_WR(0,write_addr,write_data);
      
      // Respons is the same like request
      crc = modbus_response(crc,slave_id     );
      crc = modbus_response(crc,function_code);
      crc = modbus_response(crc,0x00         );
      crc = modbus_response(crc,write_addr   );
      crc = modbus_response(crc,0x00         );
      crc = modbus_response(crc,write_data   );

      break;

    default:
            return;
    }

  modbus_response_crc(crc);

}
