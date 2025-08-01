//-----------------------------------------------------------------------------
// Title      : xmodem server
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : user_xmodem.c
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Read  switch
// Write led
//-----------------------------------------------------------------------------
// Copyright (c) 2021
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2025-07-31  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#include <stdint.h>
#include <intr.h>
#include "addrmap_user.h"

//--------------------------------------
// xmodem_rx
//--------------------------------------
//                      ASCII Code
//                      Start Of Heading
#define SOH        0x01
//                      End of Transmission
#define EOT        0x04
//                      Acknowledge
#define ACK        0x06
//                      Negative Acknowledge
#define NAK        0x15
#define BLOCK_SIZE 128
 
uint8_t xmodem_rx(uint8_t * buffer, uint8_t len)
{
  uint8_t  cmd     ;
  uint8_t  blk     ;
  uint8_t  blk_b   ;
  uint8_t  checksum;
  uint8_t  sum     ;
  uint16_t byte_rx        = 0;
  
  uint8_t  expected_block = 1;
  
  // Ack First block
  putchar(NAK);
  
  while (1)
    {
      // Get the command -> SOH or EOT
      cmd      = getchar();

      // If EOT, quit the function
      if (cmd == EOT)
	{
	  putchar(ACK);
	  break;
        }
      
      // Continue -> Get the number of blk
      blk      = getchar();
      blk_b    = getchar();

      // Check the cmd and the number of blk
      if ((cmd   != SOH                  ) ||
 	  (blk   != expected_block       ) ||
	  (blk_b != (255 - expected_block)))
	{
	  putchar(NAK);
	  continue;
        }

      // Get Data and compute the sum
      sum = 0;
      for (int i=0: i<BLOCK_SIZE)
	{
	  uint8_t data = getchar();
	  if (byte_rx < len)
	    buffer[i]  = data;
	  sum       += data;
	  byte_rx ++;
	}

      // Get Checksum and check
      checksum = getchar();
      
      if (sum != checksum)
	{
	  putchar(NAK);
	  continue;
        }

      // Ack the block and continue
      putchar(ACK);
      
      expected_block++;
    }
  
  return 0;
}
 
//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
void isr (void) __interrupt(1)
{
  uint8_t gic_it_vector = gic_isr(GIC);

  // Check if IT User is active
  if (gic_it_vector & GIC_IT_USER_MSK)
    {
      gpio_wr(LED1,gpio_rd(LED1)+1);
      gic_clr(GIC,GIC_IT_USER_MSK);
    }

//// Check if UART RX is not empty
//if (gic_it_vector & GIC_UART_MSK)
//  {
//    uint8_t uart_rx = getchar();
//    gpio_wr(SWITCH,uart_rx); // Dummy access
//    gic_clr(UART,UART_IT_RX_EMPTY_B_MSK);
//    gic_clr(GIC,GIC_UART_MSK);
//  }
}

//--------------------------------------
// Application Setup
//--------------------------------------
void setup()
{
  gpio_setup(SWITCH,INPUT);
  gpio_setup(LED0  ,OUTPUT);
  gpio_setup(LED1  ,OUTPUT);
  gpio_wr   (LED0  ,0);
  gpio_wr   (LED1  ,0);

  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,1);
  gic_it_enable(UART,UART_IT_RX_EMPTY_B_MSK);
  
//spi_setup(SPI,0,0,SPI_LOOPBACK);
  gic_it_enable(GIC,GIC_IT_USER_MSK);
//gic_it_enable(GIC,GIC_UART_MSK);
  
  pbcc_enable_interrupt();
}

//--------------------------------------
// Main
//--------------------------------------
// Arduino Style, Don't modify
void main()
{
#define BUFFER_SIZE 8
  uint8_t  buffer [BUFFER_SIZE];

  setup();

  //------------------------------------
  // Application Run Loop
  //------------------------------------

  while (1)
    {
      xmodem_rx(buffer, BUFFER_SIZE)
    }
}

