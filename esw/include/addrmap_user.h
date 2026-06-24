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
#define GIC                 0x00
#define SPINLOCK            0x02
#define SWITCH              0x04
#define LED0                0x08
#define LED1                0x0C
#define CRC                 0x10
#define MAILBOX             0x14
#define SPI                 0x18
#define UART                0x20
#define TIMER               0x28
#define RAM_GLO             0x40
#define RAM_LOC             0x80

//--------------------------------------
// IT
//--------------------------------------
#define GIC_IT_USER_MSK     0x01
#define GIC_UART_MSK        0x02
#define GIC_TIMER_MSK       0x03

#endif
