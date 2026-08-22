//-----------------------------------------------------------------------------
// Title      : Macro for spi
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : spi.h
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

#ifndef _spi_h_
#define _spi_h_

#include "SPI_csr.h"
 
#define SPI_SINGLE_READ           0x03
#define SPI_SFDP                  0x5A
#define SPI_PAGE_PROGRAM          0x02
#define SPI_WRITE_ENABLE          0x06
#define SPI_READ_SR1              0x05
#define SPI_SECTOR_ERASE          0xD8

#define SPI_TX_ENABLE             1
#define SPI_TX_DISABLE            0
#define SPI_RX_ENABLE             1
#define SPI_RX_DISABLE            0
#define SPI_LOOPBACK_ENABLE       1
#define SPI_LOOPBACK_DISABLE      0
#define SPI_LAST                  1
#define SPI_CONTINUE              0

#ifdef HAVE_SPI

#define spi_setup(_BA_,_CPOL_,_CPHA_,_LOOPBACK_) \
  do { \
  PORT_WR(_BA_   ,SPI_CFG     ,(0 \
                             | ((_LOOPBACK_)<<SPI_CFG_LOOPBACK  ) \
                             | ((_CPHA_    )<<SPI_CFG_CPHA      ) \
                             | ((_CPOL_    )<<SPI_CFG_CPOL      ) \
                             | (0           <<SPI_CFG_SPI_ENABLE))); \
  PORT_WR(_BA_  ,SPI_CFG     ,(0 \
                             | ((_LOOPBACK_)<<SPI_CFG_LOOPBACK  ) \
                             | ((_CPHA_    )<<SPI_CFG_CPHA      ) \
                             | ((_CPOL_    )<<SPI_CFG_CPOL      ) \
                             | (1           <<SPI_CFG_SPI_ENABLE))); \
  } while (0)

#define spi_cmd(_BA_,_TX_,_RX_,_LAST_,_SIZE_,_LEN_)		\
  do { \
  PORT_WR(_BA_    ,SPI_CMD ,(0 \
			    | ((_TX_  )<<SPI_CMD_ENABLE_TX)\
			    | ((_RX_  )<<SPI_CMD_ENABLE_RX)\
			    | ((_LAST_)<<SPI_CMD_LAST     )\
          | ((_SIZE_)<<SPI_CMD_SIZE     )\
			    | ((_LEN_ )<<SPI_CMD_NB_BYTES )\
          | SPI_CMD_CFG_CONFIG_RAW \
			    ));\
  } while (0)

#define spi_cmd2(_BA_,_LAST_,_LEN_)		\
  do { \
  PORT_WR(_BA_    ,SPI_CMD ,(0 \
			    | ((_LAST_)<<SPI_CMD_LAST     )\
 			    | ((_LEN_ )<<SPI_CMD_NB_BYTES )\
          | SPI_CMD_CFG_KEEP_RAW \
			    ));\
  } while (0)

#define spi_tx(_BA_,_DATA_) PORT_WR(_BA_,SPI_DATA,_DATA_)
#define spi_rx(_BA_)        PORT_RD(_BA_,SPI_DATA)

#define spi_inst(_BA_,_INSTRUCTION_,_LAST_) \
  do { \
  spi_cmd(_BA_,1,0,_LAST_,SPI_CMD_SIZE_SINGLE,0);\
  spi_tx(_BA_ ,_INSTRUCTION_);\
  } while (0)

#define spi_inst24(_BA_,_INSTRUCTION_,_ADDR_,_LAST_) \
  do { \
  spi_cmd(_BA_,1,0,_LAST_,SPI_CMD_SIZE_SINGLE,3);\
  spi_tx(_BA_ ,_INSTRUCTION_);\
  spi_tx(_BA_ ,_ADDR_>>16);\
  spi_tx(_BA_ ,_ADDR_>>8);\
  spi_tx(_BA_ ,_ADDR_>>0);\
  } while (0)


#else

#define spi_setup(_BA_,_CPOL_,_CPHA_,_LOOPBACK_)     do {} while (0)
#define spi_cmd(_BA_,_TX_,_RX_,_LAST_,_LEN_,_SIZE_)  do {} while (0)
#define spi_cmd2(_BA_,_LAST_,_LEN_)                  do {} while (0)
#define spi_inst(_BA_,_INSTRUCTION_,_LAST_)          do {} while (0)
#define spi_inst24(_BA_,_INSTRUCTION_,_ADDR_,_LAST_) do {} while (0)
#define spi_tx(_BA_,_DATA_)	                         do {} while (0)
#define spi_rx(_BA_) 0

#endif

#endif
