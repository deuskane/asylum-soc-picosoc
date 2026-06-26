//-----------------------------------------------------------------------------
// Title      : Macro for uart
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : uart.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
//-----------------------------------------------------------------------------
// Copyright (c) 2025
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2025-06-14  1.0      mrosiere Created
// 2026-06-26  1.1      mrosiere Use include from regtool
//-----------------------------------------------------------------------------

#ifndef _uart_h_
#define _uart_h_

#include "UART_csr.h"


#define UART_IT_RX_FULL         3
#define UART_IT_RX_EMPTY_B      2
#define UART_IT_TX_FULL         1
#define UART_IT_TX_EMPTY_B      0

#define UART_IT_RX_FULL_MSK     0x08
#define UART_IT_RX_EMPTY_B_MSK  0x04
#define UART_IT_TX_FULL_MSK     0x02
#define UART_IT_TX_EMPTY_B_MSK  0x01

//--------------------------------------
// putchar : send char into uart
// puthex  : translate byte into ascii and send into uart
//--------------------------------------
#ifdef HAVE_UART

#define uart_setup(_BA_,_CLOCK_FREQ_,_BAUD_RATE_,_LOOPBACK_) \
do {                                                         \
 uint16_t cnt=(((_CLOCK_FREQ_)/(_BAUD_RATE_))-1);            \
  PORT_WR(_BA_  ,UART_CTRL_TX   ,0x11 );                     \
  PORT_WR(_BA_  ,UART_CTRL_RX   ,0x11 | (_LOOPBACK_)<<3);    \
  PORT_WR(_BA_  ,UART_BAUD_TICK_CNT_MAX_LSB,cnt&0xFF);                     \
  PORT_WR(_BA_  ,UART_BAUD_TICK_CNT_MAX_MSB,(cnt>>8)&0xFF);                \
 } while (0)

#define uart_wr(_BA_,_DATA_) PORT_WR(_BA_,UART_DATA,_DATA_)
#define uart_rd(_BA_)        PORT_RD(_BA_,UART_DATA)

#define putchar(_byte_)      uart_wr(UART, _byte_)
#define getchar()            uart_rd(UART)

#define puthex(_byte_)            \
do {                              \
  uint8_t msb = (_byte_) >> 4;    \
  uint8_t lsb = (_byte_) & 0x0F;  \
                                  \
  if (msb>9)                      \
    putchar('A'+msb-10);          \
  else                            \
    putchar('0'+msb);             \
                                  \
  if (lsb>9)                      \
    putchar('A'+lsb-10);          \
  else                            \
    putchar('0'+lsb);             \
 } while (0)

#else

#define uart_setup(_BA_,_CLOCK_FREQ_,_BAUD_RATE_,_LOOPBACK_) do {} while (0)
#define getchar()            0
#define putchar(_byte_)      do {} while (0)
#define puthex(_byte_)       do {} while (0)
#define uart_wr(_BA_,_DATA_) do {} while (0)
#define uart_rd(_BA_)        0

#endif





#endif
