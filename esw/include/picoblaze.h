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
//-----------------------------------------------------------------------------

#ifndef _picoblaze_h_
#define _picoblaze_h_


//--------------------------------------
// Port Macro
//--------------------------------------
extern volatile char PBLAZEPORT[];

#define PORT_WR(_BA_,_OFFSET_,_DATA_) PBLAZEPORT[(_BA_)+(_OFFSET_)] = (_DATA_)
#define PORT_RD(_BA_,_OFFSET_)        PBLAZEPORT[(_BA_)+(_OFFSET_)]

#endif
