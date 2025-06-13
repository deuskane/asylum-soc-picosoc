//-----------------------------------------------------------------------------
// Title      : kcpsm3 file for identity fonction
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : identity.c
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
// 2017-03-30  1.0      mrosiere Created
// 2025-01-06  1.1      mrosiere Add comments
// 2025-06-13  1.2      mrosiere Add SPI
//-----------------------------------------------------------------------------

#include <stdint.h>
//#include <intr.h>

//--------------------------------------
// Port Macro
//--------------------------------------
extern char PBLAZEPORT[];

#define PORT_WR(_ADDR_,_DATA_) PBLAZEPORT[_ADDR_] = _DATA_
#define PORT_RD(_ADDR_)        PBLAZEPORT[_ADDR_]

//--------------------------------------
// Address Map
//--------------------------------------
#define SWITCH              0x10
#define LED0                0x20
#define LED1                0x40
#define UART                0x80
#define SPI                 0x08

#define UART_DATA           0x0
#define UART_CTRL           0x1
#define UART_CNT_LSB        0x2
#define UART_CNT_MSB        0x3

#define GPIO_DATA           0x0
#define GPIO_DATA_OE        0x1
#define GPIO_DATA_IN        0x2
#define GPIO_DATA_OUT       0x3

#define SPI_DATA            0x0
#define SPI_CMD             0x1
#define SPI_CFG             0x2
#define SPI_PRESCALER       0x3

//--------------------------------------
// putchar : send char into uart
// puthex  : translate byte into ascii and send into uart
//--------------------------------------
#ifdef HAVE_UART
#define putchar(c) PORT_WR(UART+UART_DATA, c)

#define puthex(byte)           \
do {			      \
  uint8_t msb = byte >> 4;    \
  uint8_t lsb = byte & 0x0F;  \
			      \
  if (msb>9)		      \
    putchar('A'+msb-10);      \
  else			      \
    putchar('0'+msb);	      \
			      \
  if (lsb>9)		      \
    putchar('A'+lsb-10);      \
  else			      \
    putchar('0'+lsb);         \
 } while (0)
#else

#define putchar(c)   do {} while (0)
#define puthex(byte) do {} while (0)

#endif

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
void isr (void) __interrupt(1)
{
  PORT_WR(LED1,PORT_RD(LED1)+1);
}

//--------------------------------------
// Main
//--------------------------------------
// Arduino Style, Don't modify
void main()
{
  uint8_t cpt = 0;

  //------------------------------------
  // Application Setup
  //------------------------------------
  // Init counter
  // Send counter to led
  // Enable interuption
  PORT_WR(SWITCH +GPIO_DATA_OE,0x00);
  PORT_WR(LED0   +GPIO_DATA_OE,0xFF);
  PORT_WR(LED1   +GPIO_DATA_OE,0xFF);

#ifdef HAVE_UART
  PORT_WR(UART   +UART_CTRL   ,0x80); // RX Use Loopback
  PORT_WR(UART   +UART_CTRL   ,0x91); // RX Use Loopback, Enable TX, Enable RX,
  PORT_WR(UART   +UART_CNT_LSB,((CLOCK_FREQ/BAUD_RATE)-1));
  PORT_WR(UART   +UART_CNT_MSB,((CLOCK_FREQ/BAUD_RATE)-1)>>8);
#endif

#ifdef HAVE_SPI
  PORT_WR(SPI    +SPI_CFG     ,(0
				| (1<<3) // Loopback
				| (0<<2) // CPHA
				| (0<<1) // CPOL
				| (0<<0) // SPI Disable
				));
  PORT_WR(SPI    +SPI_CFG     ,(0
#ifndef HAVE_SPI_MEMORY
				| (1<<3) // Loopback
#endif
				| (0<<2) // CPHA
				| (0<<1) // CPOL
				| (1<<0) // SPI Enable
				));
#endif
  
  PORT_WR(LED1,0);

  //pbcc_enable_interrupt();
  __asm
    ENABLE INTERRUPT
  __endasm;

#ifdef HAVE_SPI
  PORT_WR(SPI    +SPI_CMD ,(0
			    | (1<<7) // Enable TX
			    | (0<<6) // Enable RX
			    | (0<<5) // Last
			    | (3<<0) // 4 bytes
			    ));
  // Instruction
  PORT_WR(SPI    +SPI_DATA,0x03);
  // Address
  PORT_WR(SPI    +SPI_DATA,0x00);
  PORT_WR(SPI    +SPI_DATA,0x00);
  PORT_WR(SPI    +SPI_DATA,0x00);
#endif       

  
  //------------------------------------
  // Application Run Loop
  //------------------------------------
  // Read Switch and write to led
  while (1)
    {
      uint8_t sw = PORT_RD(SWITCH);
      uint8_t spi_rx;

#ifdef INVERT_SWITCH
      sw = ~sw;
#endif
  
      PORT_WR(LED0, sw);


#ifdef HAVE_SPI
#ifdef HAVE_SPI_MEMORY
      PORT_WR(SPI    +SPI_CMD ,(0
				| (0<<7) // Enable TX
				| (1<<6) // Enable RX
				| (0<<5) // Last
				| (0<<0) // 1 bytes
				));
#else
      PORT_WR(SPI    +SPI_CMD ,(0
				| (1<<7) // Enable TX
				| (1<<6) // Enable RX
				| (1<<5) // Last
				| (0<<0) // 1 bytes
				));
      PORT_WR(SPI    +SPI_DATA,cpt);
#endif
#endif       
      
      putchar('H');
      putchar('e');
      putchar('l');
      putchar('l');
      putchar('o');
      putchar(' ');
      puthex (sw);
      putchar(' ');

#ifdef HAVE_SPI
      spi_rx = PORT_RD(SPI    +SPI_DATA);
      puthex (spi_rx);
#else
      puthex (cpt);
#endif       
      
      putchar('\r');
      putchar('\n');

      
      cpt ++;
    }
 
}
