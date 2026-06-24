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
#include "addrmap_user.h"

static inline uint32_t read_mhartid(void)
{
  uint32_t id;
  asm volatile ("csrr %0, mhartid" : "=r" (id));
  return id;
}

typedef struct
{
  uint32_t cpt;
} app_data_t;

#define app_data (*(volatile app_data_t *)RAM_GLO)

//--------------------------------------
// Constant
//--------------------------------------
#define UART_RX_LOOPBACK 0

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
ISR_FCT
{
}

/**
 * @brief Generates an 8-bit pseudo-random number
 * @return uint8_t A number between 0 and 255
 */
uint8_t rand8(uint8_t seed) {
    // LCG Formula: X = (a * X + c) % m
    // Here, a = 137, c = 187, and the natural overflow of uint8_t handles the "% 256" (m)
    seed = (137 * seed) + 187;
    return seed;
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

  // GIC
  // * Enable the interruption User
  // * Enable Interruption from UART
  gic_it_enable(GIC,GIC_IT_USER_MSK);
  gic_it_enable(GIC,GIC_UART_MSK);

  // Setup the interruption handler address in the CPU
  interrupt_setup(isr);

  // Enable Interrtuption in the CPU
  interrupt_enable();
}

//--------------------------------------
// Main
//--------------------------------------
// Arduino Style, Don't modify
void main()
{
  uint32_t cpu_id;
  uint8_t seed; 

  // Read the CPU ID
  cpu_id = read_mhartid();
  seed   = (uint8_t)cpu_id;

  while (spinlock_try_lock(SPINLOCK,0) != 0);

  // Try to acquire the lock, if it is already locked, it means it's not the first CPU, so it will not setup the application, just run the loop
  if (spinlock_try_lock(SPINLOCK,1) == 0)
    {
      setup();

      app_data.cpt = 0;
    }
  spinlock_unlock(SPINLOCK,0);

  //------------------------------------
  // Application Run Loop
  //------------------------------------

  while (1)
    {
      uint32_t cpt;
      uint8_t  cpt_byte3;
      uint8_t  cpt_byte2;
      uint8_t  cpt_byte1;
      uint8_t  cpt_byte0;

      // Acquire the lock, wait until it is available
      while (spinlock_try_lock(SPINLOCK,0) != 0)
        {

          uint8_t wait_cpt = seed;
          seed = rand8(seed);

          while (wait_cpt-- != 0)
          {
             // __asm__ volatile tells the compiler: "Do not touch, optimize, or move this"
            __asm__ volatile ("nop"); 
          }

        }

      putchar('C');
      putchar('P');
      putchar('U');
      putchar(' ');
      
      cpt       = cpu_id;
	    //cpt_byte3 = (cpt>>24)&0xFF;
	    //cpt_byte2 = (cpt>>16)&0xFF;
	    //cpt_byte1 = (cpt>> 8)&0xFF;
	    cpt_byte0 = (cpt>> 0)&0xFF;

      //puthex (cpt_byte3);
   	  //puthex (cpt_byte2);
   	  //puthex (cpt_byte1);
   	  puthex (cpt_byte0);

      putchar(' ');
      putchar('-');
      putchar(' ');

      putchar('L');
      putchar('o');
      putchar('o');
      putchar('p');
      putchar(' ');

      // Split 32b counter into 4 bytes
      cpt       = app_data.cpt;
	    cpt_byte3 = (cpt>>24)&0xFF;
	    cpt_byte2 = (cpt>>16)&0xFF;
	    cpt_byte1 = (cpt>> 8)&0xFF;
	    cpt_byte0 = (cpt>> 0)&0xFF;

      puthex (cpt_byte3);
   	  puthex (cpt_byte2);
   	  puthex (cpt_byte1);
   	  puthex (cpt_byte0);

      putchar('\r');
      putchar('\n');

      // Increase loop counter
      app_data.cpt++;

      // Release the lock
      spinlock_unlock(SPINLOCK,0);
    }
}
