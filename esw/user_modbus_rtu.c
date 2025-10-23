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

//--------------------------------------
// Constant
//--------------------------------------
#define UART_RX_LOOPBACK 0

// CRC calculation
static uint16_t crc16_init()
{
  return 0xFFFF;
}

static uint16_t crc16_next(uint16_t crc,
			   uint8_t  data)
{
  uint8_t  i;
  crc = crc ^ data;

  for (i = 8; i != 0; i--)
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

  byte = (crc >> 8)&0xFF;
  putchar(byte);
}

uint8_t _getchar()
{
  return getchar();
}

void modbus_request()
{
  uint8_t  slave_id     ;
  uint8_t  function_code;
  uint16_t crc;
  uint8_t  i;
  
  slave_id      = _getchar();

  // Check Slave ID
  //if (slave_id != MODBUS_ADDRESS) return;

  crc           = crc16_init();
  function_code = _getchar();

  switch (function_code)
    {
    case MODBUS_FC_READ_HOLDING_REGISTERS:
      {
	// Read Holding Registers
	// Request must be 8 bytes
	// Respons must be 5+2*N bytes
      
	// Modbus uses 16b address and 16b data
	// here -> ignore MSB

	uint8_t  read_addr_msb = _getchar();
	uint8_t  read_addr_lsb = _getchar();
	uint8_t  read_addr     = read_addr_lsb; // ignore MSB
	uint8_t  read_len_msb  = _getchar();
	uint8_t  read_len_lsb  = _getchar();
	uint8_t  read_len      = read_len_lsb; // ignore MSB

	// Response :
	// Byte 0 : Slave ID
	// Byte 1 : Function Code
	// Byte 2 : Number of read bytes
	crc = modbus_response(crc,slave_id     );
	crc = modbus_response(crc,function_code);
	crc = modbus_response(crc,read_len << 1); // read_len is in read word so 16b

	// Byte 3 : read data MSB
	// Byte 4 : read data LSB
	for (i = 0; i < read_len; i++)
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
      }
    case MODBUS_FC_WRITE_SINGLE_REGISTER:
      {
	// Write Single Register

	// Modbus uses 16b address and 16b data
	// here -> ignore MSB
	uint8_t  write_addr_msb = _getchar();
	uint8_t  write_addr_lsb = _getchar();
	uint8_t  write_addr     = write_addr_lsb; // ignore MSB
	uint8_t  write_data_msb = _getchar();
	uint8_t  write_data_lsb = _getchar();
	uint8_t  write_data     = write_data_lsb; // ignore MSB

	PORT_WR(0,write_addr,write_data);
      
	// Respons is the same like request
	crc = modbus_response(crc,slave_id     );
	crc = modbus_response(crc,function_code);
	crc = modbus_response(crc,0x00         );
	crc = modbus_response(crc,write_addr   );
	crc = modbus_response(crc,0x00         );
	crc = modbus_response(crc,write_data   );

	break;
      }
      
    default:
            return;
    }

  modbus_response_crc(crc);

}

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
void isr (void) __interrupt(1)
{
  // Nothing

  // All done
}

//--------------------------------------
// Application Setup
//--------------------------------------
void setup()
{
  // GPIO Setup
  // * SWITCH is Input
  // * LED    are Output and init to 0
  gpio_setup(SWITCH,INPUT);
  gpio_setup(LED0  ,OUTPUT);
  gpio_setup(LED1  ,OUTPUT);
  gpio_wr(LED0,0);
  gpio_wr(LED1,0);

  // UART
  // * Setup the clock frequency and the target Baud Rate
  // * Configurae the Uart RX Loopback
  // * No enable interruption
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);


  // Enable Interrtuption in the CPU
  //pbcc_enable_interrupt();
}


//--------------------------------------
// Main
//--------------------------------------
// Arduino Style, Don't modify
void main()
{
  uint32_t cpt = 0;

  setup();

  //------------------------------------
  // Application Run Loop
  //------------------------------------

  while (1)
    {
      modbus_request();
    }
}
