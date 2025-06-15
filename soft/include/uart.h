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
//-----------------------------------------------------------------------------

#ifndef _uart_h_
#define _uart_h_


#define UART_DATA           0x0
#define UART_CTRL           0x1
#define UART_CNT_LSB        0x2
#define UART_CNT_MSB        0x3

//--------------------------------------
// putchar : send char into uart
// puthex  : translate byte into ascii and send into uart
//--------------------------------------
#ifdef HAVE_UART

#define uart_setup(_BA_,_CLOCK_FREQ_,_BAUD_RATE_,_LOOPBACK_) \
do {			      \
  PORT_WR(_BA_  ,UART_CTRL   ,0x00 | (_LOOPBACK_)<<7); \
  PORT_WR(_BA_  ,UART_CTRL   ,0x11 | (_LOOPBACK_)<<7); \
  PORT_WR(_BA_  ,UART_CNT_LSB,((_CLOCK_FREQ_/_BAUD_RATE_)-1)); \
  PORT_WR(_BA_  ,UART_CNT_MSB,((_CLOCK_FREQ_/_BAUD_RATE_)-1)>>8); \
 } while (0)


#define putchar(_byte_) PORT_WR(UART,UART_DATA, _byte_)

#define puthex(_byte_)          \
do {			      \
  uint8_t msb = _byte_ >> 4;    \
  uint8_t lsb = _byte_ & 0x0F;  \
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

#define uart_setup(_BA_,_CLOCK_FREQ_,_BAUD_RATE_,_LOOPBACK_) do {} while (0)
#define putchar(_byte_) do {} while (0)
#define puthex(_byte_)  do {} while (0)

#endif





#endif
