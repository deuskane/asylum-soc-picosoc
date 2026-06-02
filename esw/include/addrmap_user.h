//-----------------------------------------------------------------------------
// Title      : Macro to define Address Map for user soc
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : addrmap_user.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
//-----------------------------------------------------------------------------
// Copyright (c) 2025
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2025-07-31  1.0      mrosiere Created
// 2025-11-02  1.1      mrosiere Add Timer
// 2026-05-29  1.2      mrosiere Add SPINLOCK and MAILBOX
//-----------------------------------------------------------------------------

#ifndef _addrmap_user_h_
#define _addrmap_user_h_

//--------------------------------------
// IP
//--------------------------------------

#include "cpu.h"
#include "gpio.h"
#include "uart.h"
#include "spi.h"
#include "gic.h"
#include "timer.h"
#include "crc.h"
#include "spinlock.h"
#include "mailbox.h"

//--------------------------------------
// Address Map
//--------------------------------------
#define SWITCH              0x00
#define LED0                0x04
#define LED1                0x08
#define CRC                 0x0C
#define SPINLOCK            0x10
#define MAILBOX             0x20
#define UART                0x30
#define SPI                 0x40
#define GIC                 0x50
#define TIMER               0x60

//--------------------------------------
// IT
//--------------------------------------
#define GIC_IT_USER_MSK     0x01
#define GIC_UART_MSK        0x02
#define GIC_TIMER_MSK       0x03

#endif
