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
//-----------------------------------------------------------------------------

#ifndef _addrmap_user_h_
#define _addrmap_user_h_

//--------------------------------------
// IP
//--------------------------------------

#include "picoblaze.h"
#include "gpio.h"
#include "uart.h"
#include "spi.h"
#include "gic.h"
#include "timer.h"

//--------------------------------------
// Address Map
//--------------------------------------
#define SWITCH              0x10
#define LED0                0x20
#define LED1                0x40
#define UART                0x80
#define SPI                 0x08
#define GIC                 0xF0
#define TIMER               0xE0

//--------------------------------------
// IT
//--------------------------------------
#define GIC_IT_USER_MSK     0x01
#define GIC_UART_MSK        0x02
#define GIC_TIMER_MSK       0x03

#endif
