#include <stdint.h>

// define portu
extern char PBLAZEPORT[];

#define PORT_WR(_ADDR_,_DATA_) PBLAZEPORT[_ADDR_] = _DATA_
#define PORT_RD(_ADDR_)        PBLAZEPORT[_ADDR_]

#define LED       0x04
#define SWITCH    0x00

void main()
{
  while (1) PORT_WR(LED,PORT_RD(SWITCH));

}
