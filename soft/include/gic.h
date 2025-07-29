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
//-----------------------------------------------------------------------------

#ifndef _gic_h_
#define _gic_h_

#define GIC_ISR            0x0
#define GIC_ISM            0x1

#define gic_it_enable(_BA_,_VALUE_)    PORT_WR(_BA_,GIC_ISM,( (_VALUE_)|PORT_RD(_BA_,GIC_ISM)))
#define gic_it_disable(_BA_,_VALUE_)   PORT_WR(_BA_,GIC_ISM,(~(_VALUE_)&PORT_RD(_BA_,GIC_ISM)))
#define gic_ism(_BA_)                  PORT_RD(_BA_,GIC_ISM)
#define gic_isr(_BA_)                  PORT_RD(_BA_,GIC_ISR)
#define gic_get(_BA_)                  gic_isr(_BA_)
#define gic_clr(_BA_,_DATA_)           PORT_WR(_BA_,GIC_ISR,_DATA_)
#define gic_isr_get(_BA_,_BIT_)        ((gic_isr(_BA_)>>_BIT_)&0x01)
#define gic_isr_clr(_BA_,_BIT_)        gic_clr(_BA_,(1<<_BIT_))

#endif
