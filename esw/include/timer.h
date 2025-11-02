//-----------------------------------------------------------------------------
// Title      : Macro for timer
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : timer.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
//-----------------------------------------------------------------------------
// Copyright (c) 2025
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2025-11-02  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#ifndef _timer_h_
#define _timer_h_

#define TIMER_ISR           0x0
#define TIMER_IMR           0x1
#define TIMER_CONTROL       0x2
#define TIMER_DATA0         0x4
#define TIMER_DATA1         0x5
#define TIMER_DATA2         0x6
#define TIMER_DATA3         0x7

#define TIMER_IT_DONE       0

#define TIMER_IT_DONE_MSK   0x01

#define timer_setup(_BA_,_ENABLE_,_CLEAR_,_AUTOSTART_) PORT_WR(_BA_,TIMER_CONTROL,(((_CLEAR_)<<0)|((_ENABLE_)<<1)|((_AUTOSTART_)<<2)))
#define timer_wr(_BA_,_DATA_)  do {PORT_WR(_BA_,TIMER_DATA0,(_DATA_)>>0);PORT_WR(_BA_,TIMER_DATA1,(_DATA_)>>8);PORT_WR(_BA_,TIMER_DATA2,(_DATA_)>>16);PORT_WR(_BA_,TIMER_DATA3,(_DATA_)>>24); } while (0)

#define timer_enable(_BA_)  do {PORT_WR(_BA_,TIMER_CONTROL,(PORT_RD(_BA_,TIMER_CONTROL)|0x02));} while (0)
#define timer_disable(_BA_) do {PORT_WR(_BA_,TIMER_CONTROL,(PORT_RD(_BA_,TIMER_CONTROL)&0xFD));} while (0)
#define timer_clear(_BA_)   do {PORT_WR(_BA_,TIMER_CONTROL,(PORT_RD(_BA_,TIMER_CONTROL)|0x01));} while (0)
#define timer_unclear(_BA_) do {PORT_WR(_BA_,TIMER_CONTROL,(PORT_RD(_BA_,TIMER_CONTROL)&0xFE));} while (0)


#endif
