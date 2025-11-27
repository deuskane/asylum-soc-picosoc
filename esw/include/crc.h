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
//-----------------------------------------------------------------------------

#ifndef _crc_h_
#define _crc_h_

#define CRC_DATA0         0x0
#define CRC_DATA1         0x1
#define CRC_CRC0          0x2
#define CRC_CRC1          0x3

#define crc_rd(_BA_,_ADDR_)         PORT_RD(_BA_,CRC_##_ADDR_)
#define crc_wr(_BA_,_ADDR_,_DATA_)  PORT_WR(_BA_,CRC_##_ADDR_,_DATA_)

#endif
