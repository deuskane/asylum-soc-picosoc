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
#define RST       0x00
#define LED       0x04

//--------------------------------------
// Global Variable
//--------------------------------------
static char cpt = 0;

void null (void)
{
  // Empty
}

//--------------------------------------
// Soc User Reset
//--------------------------------------
void soc_user_reset()
{
  PORT_WR(RST,0);
  PORT_WR(RST,1);

  null ();
}

//--------------------------------------
// Interrupt Sub Routine
//--------------------------------------
void isr (void) __interrupt(1)
{
  soc_user_reset();
  cpt ++;
  PORT_WR(LED,cpt);

  null();
}

//--------------------------------------
// Application Setup
//--------------------------------------
void setup (void)
{
  soc_user_reset();
  pbcc_enable_interrupt();

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
}
