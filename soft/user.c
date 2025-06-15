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
#include <intr.h>

#include "picoblaze.h"
#include "gpio.h"
#include "uart.h"
#include "spi.h"

//--------------------------------------
// Address Map
//--------------------------------------
#define SWITCH              0x10
#define LED0                0x20
#define LED1                0x40
#define UART                0x80
#define SPI                 0x08

#ifdef HAVE_SPI_MEMORY
#define SPI_LOOPBACK 0
#else
#define SPI_LOOPBACK 1
#endif

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
void isr (void) __interrupt(1)
{
  gpio_wr(LED1,gpio_rd(LED1)+1);
}


//--------------------------------------
// Application Setup
//--------------------------------------
void setup()
{
  gpio_setup(SWITCH,INPUT);
  gpio_setup(LED0  ,OUTPUT);
  gpio_setup(LED1  ,OUTPUT);
  gpio_wr(LED0,0);
  gpio_wr(LED1,0);

  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,1);

  spi_setup(SPI,0,0,SPI_LOOPBACK);
  spi_inst24(SPI,SPI_SINGLE_READ,0x000002);

  pbcc_enable_interrupt();
}

//--------------------------------------
// Main
//--------------------------------------
// Arduino Style, Don't modify
void main()
{
  uint8_t cpt = 0;

  setup();
  
  //------------------------------------
  // Application Run Loop
  //------------------------------------
  // Read Switch and write to led
  while (1)
    {
      uint8_t sw = gpio_rd(SWITCH);
      uint8_t spi_byte;

#ifdef INVERT_SWITCH
      sw = ~sw;
#endif
  
      gpio_wr(LED0, sw);

#ifdef HAVE_SPI_MEMORY
      spi_cmd(SPI,SPI_TX_DISABLE,SPI_RX_ENABLE,SPI_LOOPBACK_DISABLE,0);
#else
      spi_cmd(SPI,SPI_TX_ENABLE,SPI_RX_ENABLE,SPI_LOOPBACK_ENABLE,0);
      spi_tx (SPI,cpt);
#endif       
      
      putchar('H');
      putchar('e');
      putchar('l');
      putchar('l');
      putchar('o');
      putchar(' ');
      puthex (cpt);
      putchar('-');
      puthex (sw);
      putchar('-');

      spi_byte = spi_rx(SPI);
      puthex (spi_byte);
      //putchar(spi_byte);
      
      putchar('\r');
      putchar('\n');

      
      cpt ++;
    }
 
}
