//-----------------------------------------------------------------------------
// Title      : Macro for crc
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : crc.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
//-----------------------------------------------------------------------------
// Copyright (c) 2025
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2025-11-02  1.0      mrosiere Created
// 2026-06-26  1.1      mrosiere Use include from regtool
//-----------------------------------------------------------------------------

#ifndef _crc_h_
#define _crc_h_

#include "crc_csr.h"

#define crc_rd(_BA_,_ADDR_)         PORT_RD(_BA_,CRC_##_ADDR_)
#define crc_wr(_BA_,_ADDR_,_DATA_)  PORT_WR(_BA_,CRC_##_ADDR_,_DATA_)

#endif
