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

//--------------------------------------
// crc16_next
// Compute one loop of CRC16
//--------------------------------------
uint16_t crc16_next(uint16_t crc,
                    uint8_t  data)
{
  crc = crc ^ data;

  if ((crc & 0x0001) != 0) {crc >>= 1; crc ^= 0xA001;} else { crc >>= 1; }
  if ((crc & 0x0001) != 0) {crc >>= 1; crc ^= 0xA001;} else { crc >>= 1; }
  if ((crc & 0x0001) != 0) {crc >>= 1; crc ^= 0xA001;} else { crc >>= 1; }
  if ((crc & 0x0001) != 0) {crc >>= 1; crc ^= 0xA001;} else { crc >>= 1; }
  if ((crc & 0x0001) != 0) {crc >>= 1; crc ^= 0xA001;} else { crc >>= 1; }
  if ((crc & 0x0001) != 0) {crc >>= 1; crc ^= 0xA001;} else { crc >>= 1; }
  if ((crc & 0x0001) != 0) {crc >>= 1; crc ^= 0xA001;} else { crc >>= 1; }
  if ((crc & 0x0001) != 0) {crc >>= 1; crc ^= 0xA001;} else { crc >>= 1; }

  return crc;
}

//--------------------------------------
// modbus_response
// send byte to uart and accumulate into crc
//--------------------------------------
uint16_t modbus_response (uint16_t crc,
                          uint8_t  byte
                          )
{
  putchar(byte);
  return crc16_next(crc,byte);
}

//--------------------------------------
// modbus_response_crc
// send the crc to uart (LSB first)
//--------------------------------------
void modbus_response_crc (uint16_t crc)
{
  uint8_t byte;

  byte = crc & 0xFF;
  putchar(byte); // CRC : send LSB first

  byte = (crc >> 8)&0xFF;
  putchar(byte);
}

//--------------------------------------
// _getchar
// fonction to wrap macro getchar
//--------------------------------------
uint8_t _getchar()
{
  return getchar();
}

//--------------------------------------
// modbus_wait
// Wait 3.5T
//--------------------------------------
void modbus_wait ()
{
  uint8_t status;
  
  timer_unclear(TIMER);
  timer_enable (TIMER);

  do
    {
      status = PORT_RD(TIMER,TIMER_ISR);
    }
  while ((status&0x01) == 0x00);
  
  timer_disable(TIMER);
  timer_clear  (TIMER);
}

//--------------------------------------
// modbus_client
// send byte to uart and accumulate into crc
//--------------------------------------
void modbus_client ()
{
  uint8_t  slave_id     ;
  uint8_t  function_code;
  uint16_t crc          ;
  uint8_t  errcode      ;

  // not yet error
  errcode       = 0;

  // Get Slave ID and check
  slave_id      = _getchar();

  if (slave_id != MODBUS_ADDRESS)
    return;

  // Get Function code
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
	uint8_t  crc_rx_lsb    = _getchar();
	uint8_t  crc_rx_msb    = _getchar();
	uint16_t crc_rx       ;
	uint8_t  i            ;

	crc_rx         = (crc_rx_msb<<8)|crc_rx_lsb;

	// crc after address = 1 and read
	crc = 0xFFFF;
	crc = crc16_next(crc,slave_id      );
	crc = crc16_next(crc,function_code );
	crc = crc16_next(crc,read_addr_msb);
	crc = crc16_next(crc,read_addr_lsb);
	crc = crc16_next(crc,read_len_msb);
	crc = crc16_next(crc,read_len_lsb);

	// If CRC is different, just ignore
	if (crc_rx != crc)
	  break;

	// Supported Only 8b Address
	if (read_addr_msb != 0x00)
	  {
	    errcode = MODBUS_ERR_INVALID_ADDR;
	    break;
	  }

	// Supported Only 8b  
	if (read_len_msb != 0x00)
	  {
	    errcode = MODBUS_ERR_INVALID_DATA;
	    break;
	  }
        
	// Response :
	// Byte 0 : Slave ID
	// Byte 1 : Function Code
	// Byte 2 : Number of read bytes
	crc = 0xFFFF;
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

	modbus_response_crc(crc);
      
	break;
      }

    case MODBUS_FC_WRITE_SINGLE_REGISTER:
      {
	// Write Single Register
	uint8_t  write_addr_msb ;
	uint8_t  write_addr_lsb ;
	uint8_t  write_data_msb ;
	uint8_t  write_data_lsb ;
	uint8_t  crc_rx_lsb     ;
	uint8_t  crc_rx_msb     ;
	uint16_t crc_rx         ;

	// Modbus uses 16b address and 16b data
	// here -> ignore MSB
            
	write_addr_msb = _getchar();
	write_addr_lsb = _getchar();
	write_data_msb = _getchar();
	write_data_lsb = _getchar();
	crc_rx_lsb     = _getchar();
	crc_rx_msb     = _getchar();
	crc_rx         = (crc_rx_msb<<8)|crc_rx_lsb;
            
	// crc after address = 1 and write
	crc = 0xFFFF;
	crc = crc16_next(crc,slave_id      );
	crc = crc16_next(crc,function_code );
	crc = crc16_next(crc,write_addr_msb);
	crc = crc16_next(crc,write_addr_lsb);
	crc = crc16_next(crc,write_data_msb);
	crc = crc16_next(crc,write_data_lsb);

	// If CRC is different, just ignore
	if (crc_rx != crc)
	  break;

	// Supported Only 8b Address
	if (write_addr_msb != 0x00)
	  {
	    errcode = MODBUS_ERR_INVALID_ADDR;
	    break;
	  }

	// Supported Only 8b  
	if (write_data_msb != 0x00)
	  {
	    errcode = MODBUS_ERR_INVALID_DATA;
	    break;
	  }
            
	PORT_WR(0,write_addr_lsb,write_data_lsb);
      
	// Respons is the same like request
	crc = 0XFFFF;
	crc = modbus_response(crc,slave_id      ); 
	crc = modbus_response(crc,function_code ); 
	crc = modbus_response(crc,0x00          ); 
	crc = modbus_response(crc,write_addr_lsb); 
	crc = modbus_response(crc,0x00          ); 
	crc = modbus_response(crc,write_data_lsb); 
	modbus_response_crc(crc);
            
	break;
      }
          
      // Unsupported Function
    default:
      {
	errcode = MODBUS_ERR_INVALID_FUNC;
	break;
      }
          
    }

  // Have Error ?
  if (errcode != 0)
    {
      crc = 0XFFFF;
      crc = modbus_response(crc,slave_id      ); 
      crc = modbus_response(crc,(function_code|0x80)); 
      crc = modbus_response(crc,errcode       ); 
      modbus_response_crc(crc);
    }
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
  uint32_t timer_cnt;
  
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

  // TIMER
  // * Setup time for 3.5 STOP char
  //   Char = 1 START + 8 DATA + 1 STOP -> 10b
  //   Tchar = 10*CLOCK_FREQ/BAUD_RATE
  timer_cnt = (3.5 * 10 * CLOCK_FREQ)/(BAUD_RATE);
  timer_wr(TIMER,timer_cnt);
  gic_it_enable(TIMER,TIMER_IT_DONE_MSK);
  
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
      modbus_wait   ();
      modbus_client ();
    }
}
