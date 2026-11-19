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
// 2026-11-19  1.2      mrosiere Interrupt sources of asylum:communication:uart
//                               3.0.0 : bit 0 is TX FIFO empty, RX errors 7:4
//-----------------------------------------------------------------------------

#ifndef _uart_h_
#define _uart_h_

#include "UART_csr.h"


// Interrupt sources (bits of isr / imr, asylum:communication:uart >= 3.0.0)
// Bits 3:0 are levels (FIFO state), bits 7:4 are events (write 1 in isr to clear)
#define UART_IT_RX_BREAK        7 // RX break (all bits of a frame at 0)
#define UART_IT_RX_PARITY       6 // RX parity error
#define UART_IT_RX_FRAMING      5 // RX framing error (stop bit at 0)
#define UART_IT_RX_OVERRUN      4 // RX overrun (a received byte was dropped)
#define UART_IT_RX_FULL         3 // RX FIFO full
#define UART_IT_RX_EMPTY_B      2 // RX FIFO not empty
#define UART_IT_TX_FULL         1 // TX FIFO full
#define UART_IT_TX_EMPTY        0 // TX FIFO empty (TX FIFO not empty up to uart 2.0.0)

#define UART_IT_RX_BREAK_MSK    0x80
#define UART_IT_RX_PARITY_MSK   0x40
#define UART_IT_RX_FRAMING_MSK  0x20
#define UART_IT_RX_OVERRUN_MSK  0x10
#define UART_IT_RX_FULL_MSK     0x08
#define UART_IT_RX_EMPTY_B_MSK  0x04
#define UART_IT_TX_FULL_MSK     0x02
#define UART_IT_TX_EMPTY_MSK    0x01

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
