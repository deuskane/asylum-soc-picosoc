//-----------------------------------------------------------------------------
// Title      : Macro for gic
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : gic.h
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

#ifndef _gic_h_
#define _gic_h_

#include "GIC_csr.h"

#define gic_it_enable(_BA_,_VALUE_)    PORT_WR(_BA_,GIC_IMR,( (_VALUE_)|PORT_RD(_BA_,GIC_IMR)))
#define gic_it_disable(_BA_,_VALUE_)   PORT_WR(_BA_,GIC_IMR,(~(_VALUE_)&PORT_RD(_BA_,GIC_IMR)))
#define gic_imr(_BA_)                  PORT_RD(_BA_,GIC_IMR)
#define gic_isr(_BA_)                  PORT_RD(_BA_,GIC_ISR)
#define gic_get(_BA_)                  gic_isr(_BA_)
#define gic_clr(_BA_,_DATA_)           PORT_WR(_BA_,GIC_ISR,_DATA_)

#endif
