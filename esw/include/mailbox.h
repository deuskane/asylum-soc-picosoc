//-----------------------------------------------------------------------------
// Title      : Macro for Mailbox
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : mailbox.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// Interface for Mailbox FIFO management.
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-05-31  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#ifndef _mailbox_h_
#define _mailbox_h_

// FIFO Addresses
#define MAILBOX_FIFO0      0x0
#define MAILBOX_FIFO1      0x2

// Push: Writes data to the specified FIFO (_ID_: 0 or 1)
#define mailbox_push(_BA_, _ID_, _VAL_) PORT_WR(_BA_, MAILBOX_FIFO##_ID_, _VAL_)

// Pop: Reads data from the specified FIFO (_ID_: 0 or 1)
#define mailbox_pop(_BA_, _ID_)         PORT_RD(_BA_, MAILBOX_FIFO##_ID_)
#define mailbox_pop0(_BA_)              mailbox_pop(_BA_, 0)

#endif