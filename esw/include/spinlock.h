//-----------------------------------------------------------------------------
// Title      : Macro for spinlock
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : spinlock.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-05-30  1.0      mrosiere Created
// 2026-06-26  1.1      mrosiere Use include from regtool
//-----------------------------------------------------------------------------

#ifndef _spinlock_h_
#define _spinlock_h_

#include "spinlock_csr.h"

// Read Set   : Returns 0 if lock acquired (was 0, now set to 1), 1 if already locked.
#define spinlock_try_lock(_BA_,_ID_) PORT_RD(_BA_,SPINLOCK_LOCK##_ID_)

// Write 0 Clear : Release the lock by writing 0.
#define spinlock_unlock(_BA_,_ID_)   PORT_WR(_BA_,SPINLOCK_LOCK##_ID_,0x00)

#endif