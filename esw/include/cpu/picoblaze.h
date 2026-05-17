//-----------------------------------------------------------------------------
// Title      : Macro for picoblaze
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : picoblaze.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
//-----------------------------------------------------------------------------
// Copyright (c) 2025
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2025-06-14  1.0      mrosiere Created
// 2026-05-14  1.1      mrosiere Support others picoblaze cores 
//                               (but keep the same interface)
//-----------------------------------------------------------------------------

#ifndef _picoblaze_h_
#define _picoblaze_h_

#include <stdint.h>

//--------------------------------------
// Port Macro
//--------------------------------------
#include "intr.h"

// This variable is defined in the picoblaze compiler
extern volatile uint8_t PBLAZEPORT[];

#define PORT_WR(_BA_,_OFFSET_,_DATA_) PBLAZEPORT[(_BA_)+(_OFFSET_)] = (_DATA_)
#define PORT_RD(_BA_,_OFFSET_)        PBLAZEPORT[(_BA_)+(_OFFSET_)]


#endif
