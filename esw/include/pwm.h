//-----------------------------------------------------------------------------
// Title      : Macro for pwm
// Project    : Asylum
//-----------------------------------------------------------------------------
// File       : pwm.h
// Author     : mrosiere
//-----------------------------------------------------------------------------
// Description:
// sbi_PWM (asylum:component:PWM) : a tick lasts (prescaler+1) clock
// cycles, the PWM period (period+1) ticks, the output is high during the
// first duty ticks of each period
//-----------------------------------------------------------------------------
// Copyright (c) 2026
//-----------------------------------------------------------------------------
// Revisions  :
// Date        Version  Author   Description
// 2026-11-21  1.0      mrosiere Created
//-----------------------------------------------------------------------------

#ifndef _pwm_h_
#define _pwm_h_

#include "PWM_csr.h"

// pwm_setup   : configuration written while disabled (counter cleared,
//               output low)
// pwm_enable  : the first period starts with its high phase
// pwm_disable : counter cleared, output low
// pwm_duty    : new duty, used from the next PWM period
#define pwm_setup(_BA_,_PRESCALER_,_PERIOD_,_DUTY_) \
  do {                                              \
    pwm_disable(_BA_);                              \
    PORT_WR(_BA_,PWM_PRESCALER,_PRESCALER_);        \
    PORT_WR(_BA_,PWM_PERIOD   ,_PERIOD_);           \
    PORT_WR(_BA_,PWM_DUTY     ,_DUTY_);             \
  } while (0)

#define pwm_enable(_BA_)       PORT_WR(_BA_,PWM_CFG,PORT_RD(_BA_,PWM_CFG) |  (1<<PWM_CFG_ENABLE))
#define pwm_disable(_BA_)      PORT_WR(_BA_,PWM_CFG,PORT_RD(_BA_,PWM_CFG) & ~(1<<PWM_CFG_ENABLE))
#define pwm_duty(_BA_,_DUTY_)  PORT_WR(_BA_,PWM_DUTY,_DUTY_)

#endif
