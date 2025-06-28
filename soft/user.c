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
#define SPI_LOOPBACK SPI_LOOPBACK_DISABLE
#else
#define SPI_LOOPBACK SPI_LOOPBACK_ENABLE
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

  pbcc_enable_interrupt();
}

//--------------------------------------
// Serial Flash Discoverable Parameters
//--------------------------------------
void spi_sfdp()
{
  uint8_t dummy;
  
  spi_inst24(SPI,SPI_SFDP,0x000000,SPI_CONTINUE);
  spi_cmd(SPI,SPI_TX_DISABLE,SPI_RX_ENABLE,SPI_LAST,4-1);

  // SFDP_HEADER[0] : SFDP Signature
  putchar(spi_rx(SPI)); // 7:0
  putchar(spi_rx(SPI)); // 15:8
  putchar(spi_rx(SPI)); // 23:16
  putchar(spi_rx(SPI)); // 31:24
  putchar('\r');
  putchar('\n');
}

//--------------------------------------
// SPI Write Value
//--------------------------------------
void spi_wait_device_ready()
{
  uint8_t byte;
  

  do
    {
      spi_inst  (SPI,SPI_READ_SR1,SPI_CONTINUE);
      spi_cmd   (SPI,SPI_TX_DISABLE,SPI_RX_ENABLE,SPI_LAST,1-1);
      byte = spi_rx(SPI);     
    }
  while((byte&0x01)==0x01);
  
}

//--------------------------------------
// SPI Write Value
//--------------------------------------
void spi_write()
{
  uint8_t dummy;
  
  spi_inst  (SPI,SPI_WRITE_ENABLE,SPI_LAST);
  spi_inst24(SPI,SPI_PAGE_PROGRAM,0x000000,SPI_CONTINUE);
  spi_cmd(SPI,SPI_TX_ENABLE,SPI_RX_DISABLE,SPI_LAST,14-1);
  spi_tx (SPI,'H');
  spi_tx (SPI,'e');
  spi_tx (SPI,'l');
  spi_tx (SPI,'l');
  spi_tx (SPI,'o');
  spi_tx (SPI,' ');
  spi_tx (SPI,'P');
  spi_tx (SPI,'i');
  spi_tx (SPI,'c');
  spi_tx (SPI,'o');
  spi_tx (SPI,'S');
  spi_tx (SPI,'o');
  spi_tx (SPI,'C');
  spi_tx (SPI,'\0');

  spi_wait_device_ready();
}

//--------------------------------------
// SPI Read Value
//--------------------------------------
void spi_read()
{
  uint8_t rx;
  
  spi_inst24(SPI,SPI_SINGLE_READ,0x000000,SPI_CONTINUE);

  do
    {
      spi_cmd(SPI,SPI_TX_DISABLE,SPI_RX_ENABLE,SPI_CONTINUE,1-1);
      rx = spi_rx(SPI);
      putchar(rx);
    }
  while (rx != '\0');

  spi_cmd(SPI,SPI_TX_DISABLE,SPI_RX_DISABLE,SPI_LAST,1-1);
      
  
  putchar('\r');
  putchar('\n');
}

//--------------------------------------
// SPI Write Value
//--------------------------------------
void spi_sector_erase()
{
  spi_inst  (SPI,SPI_WRITE_ENABLE,SPI_LAST);
  spi_inst24(SPI,SPI_SECTOR_ERASE,0x000000,SPI_LAST);

  spi_wait_device_ready();
}

//--------------------------------------
// Printf
//--------------------------------------
void printf(char * x)
{
  uint8_t i=0;
  while (x[i] != '\0')
    putchar(x[i++]);
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
  // SPI Memory Validation
  //------------------------------------
#ifdef HAVE_SPI_MEMORY
  /*
  spi_sector_erase();
  spi_write();
  spi_read ();

  while(1);
  */
#endif  
  //------------------------------------
  // Application Run Loop
  //------------------------------------

  spi_inst24(SPI,SPI_SINGLE_READ,0x000000,SPI_CONTINUE);

  while (1)
    {
      uint8_t sw = gpio_rd(SWITCH);
      uint8_t spi_byte;
      uint8_t cnt_byte3,cnt_byte2,cnt_byte1,cnt_byte0;
#ifdef INVERT_SWITCH
      sw = ~sw;
#endif
  
      gpio_wr(LED0, sw);

#ifdef HAVE_SPI_MEMORY
      spi_cmd(SPI,SPI_TX_DISABLE,SPI_RX_ENABLE,SPI_CONTINUE,0);
#else
      spi_cmd(SPI,SPI_TX_ENABLE,SPI_RX_ENABLE,SPI_LAST,0);
      spi_tx (SPI,cpt);
#endif       

      // Print Msg
      putchar('L');
      putchar('o');
      putchar('o');
      putchar('p');
      putchar(' ');

      // Print 32b counter
      cnt_byte3 = (cpt>>24)&0xFF;
      cnt_byte2 = (cpt>>16)&0xFF;
      cnt_byte1 = (cpt>> 8)&0xFF;
      cnt_byte0 = (cpt>> 0)&0xFF;
      puthex (cnt_byte3);
      puthex (cnt_byte2);
      puthex (cnt_byte1);
      puthex (cnt_byte0);

      // Print 32b Switch
      putchar('-');
      puthex (sw);

      // Print SPI Byte @ cpt
      putchar('-');

      spi_byte = spi_rx(SPI);
      puthex (spi_byte);
      
      putchar('\r');
      putchar('\n');

      
      cpt ++;
    }
 
}
