#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# Title      : JTAG over the UART of PicoSoC : link OpenOCD remote_bitbang
#              to the serial port
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : remote_bitbang_setup.sh
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Board in mode 11 (switches S5 S6 = 11, JTAG over the UART) :
#              links the TCP port of the OpenOCD adapter remote_bitbang
#              (remote_bitbang.cfg : 127.0.0.1:9824) to the serial port of
#              the USB-UART cable, at the JTAG_BAUD_RATE of the bitstream
#              (9600 on the NG-MEDIUM targets).
#                tools/openocd/remote_bitbang_setup.sh [device] [baud] [port]
#                (default : /dev/ttyUSB0 9600 9824)
#              then, in another terminal :
#                openocd -f tools/openocd/remote_bitbang.cfg -f tools/openocd/picosoc.cfg
#              The serial port is set by stty (raw, 8N1, no flow control) ;
#              socat only copies the bytes, without termios option (socat
#              termios options can fail with "Inappropriate ioctl for
#              device"). One OpenOCD session after the other (fork : the
#              link stays for the next session). Ctrl-C stops the link.
#              Without read / write access to the device, stty and socat run
#              with sudo ; to avoid sudo, add the user to the group of the
#              device (dialout) : sudo usermod -aG dialout $USER, then log
#              out and in.
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-26  1.0      mrosiere Created
#-----------------------------------------------------------------------------

set -euo pipefail

DEV=${1:-/dev/ttyUSB0}
BAUD=${2:-9600}
PORT=${3:-9824}

if ! command -v socat > /dev/null
then
    echo "Error : socat not found (CentOS / Rocky : sudo dnf install socat)" >&2
    exit 1
fi

if [ ! -c "${DEV}" ]
then
    echo "Error : ${DEV} is not a serial port (cable plugged ? After OpenOCD with ft232r.cfg, unplug and plug the cable)" >&2
    exit 1
fi

# Access to the device : sudo when the user is not in its group
SUDO=""
if [ ! -r "${DEV}" ] || [ ! -w "${DEV}" ]
then
    echo "No read / write access to ${DEV} : stty and socat run with sudo"
    echo "(to avoid it : sudo usermod -aG $(stat -c %G "${DEV}") ${USER}, then log out and in)"
    SUDO=sudo
fi

# Serial port : raw bytes, 8N1, no flow control (RTS / CTS are not used in
# mode 11), DTR kept when the port is closed
${SUDO} stty -F "${DEV}" "${BAUD}" raw -echo -echoe -echok -echoctl -echoke \
        cs8 -cstopb -parenb -crtscts -ixon -ixoff -hupcl clocal

echo "JTAG over the UART : 127.0.0.1:${PORT} (OpenOCD remote_bitbang) <-> ${DEV} at ${BAUD} baud"
echo "Board  : switches S5 S6 = 11, bitstream with JTAG_BAUD_RATE = ${BAUD}"
echo "OpenOCD: openocd -f tools/openocd/remote_bitbang.cfg -f tools/openocd/picosoc.cfg"
echo "Ctrl-C to stop"

exec ${SUDO} socat TCP-LISTEN:"${PORT}",bind=127.0.0.1,reuseaddr,fork OPEN:"${DEV}",rdwr,noctty
