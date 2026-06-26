//-----------------------------------------------------------------------------
// Title      : Macro for gpio
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : gpio.h
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

#ifndef _gpio_h_
#define _gpio_h_

#include "GPIO_csr.h"

#define GPIO_OUTPUT         0xFF
#define GPIO_INPUT          0x00

#define gpio_setup(_BA_,_OE_) PORT_WR(_BA_,GPIO_DATA_OE,GPIO_##_OE_)
#define gpio_rd(_BA_)         PORT_RD(_BA_,GPIO_DATA)
#define gpio_wr(_BA_,_DATA_)  PORT_WR(_BA_,GPIO_DATA,_DATA_)

#endif
