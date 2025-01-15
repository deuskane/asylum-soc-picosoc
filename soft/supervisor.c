#include <intr.h>
#include <stdint.h>

//--------------------------------------
// Port Macro
//--------------------------------------
extern char PBLAZEPORT[];

#define PORT_WR(_ADDR_,_DATA_) PBLAZEPORT[_ADDR_] = _DATA_
#define PORT_RD(_ADDR_)        PBLAZEPORT[_ADDR_]

//--------------------------------------
// Address Map
//--------------------------------------
#define RST            0x00
#define LED            0x04
#define IT_VECTOR_MASK 0x08
#define IT_VECTOR      0x0C

#define GPIO_DATA      0x0
#define GPIO_DATA_OE   0x1
#define GPIO_DATA_IN   0x2
#define GPIO_DATA_OUT  0x3

#define VECTOR_MASK_DEFAULT 0x7
//--------------------------------------
// Global Variable
//--------------------------------------
static char cpt = 0;

void null (void)
{
  // Empty
}

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
#ifdef SAFETY_TMR
void isr (void) __interrupt(1)
{
  uint8_t it_vector;

  it_vector = PORT_RD(IT_VECTOR);
  
  if (it_vector == VECTOR_MASK_DEFAULT)
    {
      // Not the first error
      PORT_WR(RST,0);
      PORT_WR(IT_VECTOR_MASK,VECTOR_MASK_DEFAULT);
      cpt ++;
      PORT_WR(LED,cpt);
      PORT_WR(RST,1);
      null();
    }
  else
    {
      // First error
      PORT_WR(IT_VECTOR_MASK,~it_vector);
      null();
    }

  null();
}

#else

void isr (void) __interrupt(1)
{
  PORT_WR(RST,0);
  PORT_WR(IT_VECTOR_MASK,VECTOR_MASK_DEFAULT);
  cpt ++;
  PORT_WR(LED,cpt);
  PORT_WR(RST,1);
  
  null();
}

#endif
//--------------------------------------
// Application Setup
//--------------------------------------
void setup (void)
{
  PORT_WR(RST,0);

  cpt = 0;
  // Mask Enable
  PORT_WR(IT_VECTOR_MASK,VECTOR_MASK_DEFAULT);
  pbcc_enable_interrupt();

  PORT_WR(RST,1);
  
  null ();
}

//--------------------------------------
// Application Run Loop
//--------------------------------------
void loop (void)
{
  null ();
}

//--------------------------------------
// Main
//--------------------------------------
void main()
{
  setup ();

  while (1);
  //    loop ();

  null();
}
