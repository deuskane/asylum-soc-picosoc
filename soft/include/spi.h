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
//-----------------------------------------------------------------------------

#ifndef _spi_h_
#define _spi_h_

#define SPI_DATA                  0x0
#define SPI_CMD                   0x1
#define SPI_CFG                   0x2
#define SPI_PRESCALER             0x3
			          
#define SINGLE_READ               0x03
#define SFDP                      0x5A
#define SPI_TX_ENABLE             1
#define SPI_TX_DISABLE            0
#define SPI_RX_ENABLE             1
#define SPI_RX_DISABLE            0
#define SPI_LOOPBACK_ENABLE       1
#define SPI_LOOPBACK_DISABLE      0

#ifdef HAVE_SPI

#define spi_setup(_BA_,_CPOL_,_CPHA_,_LOOPBACK_) \
  do { \
  PORT_WR(_BA_   ,SPI_CFG     ,(0 \
                             | (_LOOPBACK_<<3) \
                             | (_CPHA_    <<2) \
                             | (_CPOL_    <<1) \
                             | (0         <<0))); \
  PORT_WR(_BA_  ,SPI_CFG     ,(0 \
                             | (_LOOPBACK_<<3) \
                             | (_CPHA_    <<2) \
                             | (_CPOL_    <<1) \
                             | (1         <<0))); \
  } while (0)

#define spi_cmd(_BA_,_TX_,_RX_,_LAST_,_LEN_)		\
  do { \
  PORT_WR(_BA_    ,SPI_CMD ,(0 \
			    | (_TX_  <<7)\
			    | (_RX_  <<6)\
			    | (_LAST_<<5)\
			    | (_LEN_ <<0)\
			    ));\
  } while (0)

#define spi_tx(_BA_,_DATA_) PORT_WR(_BA_,SPI_DATA,_DATA_)
#define spi_rx(_BA_)        PORT_RD(_BA_,SPI_DATA)

#define spi_inst24(_BA_,_INSTRUCTION_,_ADDR_) \
  do { \
  spi_cmd(_BA_,1,0,0,3);\
  spi_tx(_BA_ ,_INSTRUCTION_);\
  spi_tx(_BA_ ,_ADDR_>>16);\
  spi_tx(_BA_ ,_ADDR_>>8);\
  spi_tx(_BA_ ,_ADDR_>>0);\
  } while (0)


#else

#define spi_setup(_BA_,_CPOL_,_CPHA_,_LOOPBACK_) do {} while (0)
#define spi_cmd(_BA_,_TX_,_RX_,_LAST_,_LEN_)	 do {} while (0)
#define spi_inst24(_BA_,_INSTRUCTION_,_ADDR_)    do {} while (0)
#define spi_tx(_BA_,_DATA_)	                 do {} while (0)
#define spi_rx(_BA_) 0

#endif


#endif
