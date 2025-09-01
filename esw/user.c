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
#include "addrmap_user.h"

//--------------------------------------
// Constant
//--------------------------------------
#ifdef HAVE_SPI_MEMORY
// Disable SPI loobpack to communicate with the SPI Memory
#define SPI_LOOPBACK SPI_LOOPBACK_DISABLE
#else
#define SPI_LOOPBACK SPI_LOOPBACK_ENABLE
#endif

#define UART_RX_LOOPBACK 0

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
void isr (void) __interrupt(1)
{
  // GIC : Get interruption status
  uint8_t gic_it_vector = gic_isr(GIC);

  // ... Check if IT User is active
  if (gic_it_vector & GIC_IT_USER_MSK)
    {
      // Increase the LED1 counter
      gpio_wr(LED1,gpio_rd(LED1)+1);

      // Ack the interruption
      gic_clr(GIC,GIC_IT_USER_MSK);
    }

  // ... Check if UART RX is not empty
  if (gic_it_vector & GIC_UART_MSK)
    {
      // Get UART RX and echo 
      uint8_t uart_rx = getchar();
      putchar(uart_rx);
      
      //gpio_wr(SWITCH,uart_rx); // Dummy access

      // Ack the interruption (in UART and in GIC)
      gic_clr(UART,UART_IT_RX_EMPTY_B_MSK);
      gic_clr(GIC,GIC_UART_MSK);
    }

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
  // * Enable the Interruption UART RX Empty interuption
  uart_setup(UART,CLOCK_FREQ,BAUD_RATE,UART_RX_LOOPBACK);
  gic_it_enable(UART,UART_IT_RX_EMPTY_B_MSK);

  // SPI
  // * Configure CPOL / CPHA
  // * Configure SPI Loopback
  spi_setup(SPI,0,0,SPI_LOOPBACK);

  // GIC
  // * Enable the interruption User
  // * Enable Interruption from UART
  gic_it_enable(GIC,GIC_IT_USER_MSK);
  gic_it_enable(GIC,GIC_UART_MSK);

  // Enable Interrtuption in the CPU
  pbcc_enable_interrupt();
}

//--------------------------------------
// Serial Flash Discoverable Parameters
//--------------------------------------
void spi_sfdp()
{
  uint8_t dummy;

  // Execute instruction SFDP with @0 and get 4 bytes
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

  // Read the Status register 1 in continue and check the bit 1 (WIP)
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
//
// Write String in @0 of the flash
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
//
// Read spi memory @0 and display character until first '\0'
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
// SPI Sector Erase
//
// Send Sector erase command at the first sector
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

#ifdef HAVE_SPI_MEMORY
  spi_inst24(SPI,SPI_SINGLE_READ,0x000000,SPI_CONTINUE);
#endif  

  putchar('W');
  putchar('e');
  putchar('l');
  putchar('c');
  putchar('o');
  putchar('m');
  putchar('e');
  putchar(' ');
  putchar('B');
  putchar('a');
  putchar('c');
  putchar('k');
  putchar(',');
  putchar(' ');
  putchar('C');
  putchar('o');
  putchar('m');
  putchar('m');
  putchar('a');
  putchar('n');
  putchar('d');
  putchar('e');
  putchar('r');
  putchar('\r');
  putchar('\n');

  while (1)
    {
      // Read Switch
      uint8_t sw   = gpio_rd(SWITCH);

      // Get switch[5]
      if (sw&0x20)
	{
	  uint8_t spi_byte;
	  uint8_t cpt_byte3,cpt_byte2,cpt_byte1,cpt_byte0;

	  // Split 32b counter into 4 bytes
	  cpt_byte3 = (cpt>>24)&0xFF;
	  cpt_byte2 = (cpt>>16)&0xFF;
	  cpt_byte1 = (cpt>> 8)&0xFF;
	  cpt_byte0 = (cpt>> 0)&0xFF;

	  // SPI : Read 1 byte
	  // ... if spi memory, read 1 byte from memory
	  // ... if no spi memory, write cpt_byte0 and read with spi loopback
#ifdef HAVE_SPI_MEMORY
	  spi_cmd(SPI,SPI_TX_DISABLE,SPI_RX_ENABLE,SPI_CONTINUE,0);
#else
	  spi_cmd(SPI,SPI_TX_ENABLE,SPI_RX_ENABLE,SPI_LAST,0);
	  spi_tx (SPI,cpt_byte0);
#endif       

	  // Print Message
	  putchar('L');
	  putchar('o');
	  putchar('o');
	  putchar('p');
	  putchar(' ');

	  // Print 32b counter
	  puthex (cpt_byte3);
	  puthex (cpt_byte2);
	  puthex (cpt_byte1);
	  puthex (cpt_byte0);

	  // Print 8b Switch
	  putchar('-');
	  puthex (sw);

	  // Print SPI Byte @ cpt
	  putchar('-');
	  spi_byte = spi_rx(SPI);
	  puthex (spi_byte);
      
	  putchar('\r');
	  putchar('\n');

	  // Increase loop counter
	  cpt ++;
	}

      
      // Send Switch value into LEDO0
#ifdef INVERT_SWITCH
      sw = ~sw;
#endif

      gpio_wr(LED0, sw);
      
    }

  
}
