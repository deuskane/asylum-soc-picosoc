#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# Title      : Terminal on the UART of the PicoSoC board
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : uart.sh
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Opens screen on the serial port of the USB-UART cable, in a new
#              xterm window (or in the current terminal without X display or
#              without xterm) :
#                tools/uart/uart.sh [device] [baud]
#                (default : /dev/ttyUSB0 9600, the baud rate of the user UART
#                of the NG-MEDIUM targets ; 115200 and 921600 for other
#                bitstreams)
#              Board : switches S5 S6 = 00 (user UART). No flow control
#              (RTS / CTS not needed).
#              Checks : screen installed, the device is a serial port (not a
#              regular file left by a command run with sudo on a missing
#              port), the port is free (screen, socat, cat, OpenOCD),
#              access to the port (sudo otherwise ; to avoid it :
#              sudo usermod -aG dialout $USER, then log out and in).
#              Quit screen : Ctrl-A, then k, then y.
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-27  1.0      mrosiere Created : screen in xterm
# 2026-11-27  1.1      mrosiere Device and baud rate as arguments, checks,
#                               sudo when needed, screen in the current
#                               terminal without xterm
#-----------------------------------------------------------------------------

set -euo pipefail

usage()
{
    sed -n '/^# Description:/,/^#----/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; /^---/d'
    exit "${1:-1}"
}

error()
{
    echo "Error : $*" >&2
    exit 1
}

case "${1:-}" in
    -h|--help) usage 0 ;;
esac

DEV=${1:-/dev/ttyUSB0}
BAUD=${2:-9600}

command -v screen > /dev/null || error "screen not found (CentOS / Rocky : sudo dnf install screen)"

if [ -e "${DEV}" ] && [ ! -c "${DEV}" ]
then
    error "${DEV} is not a serial port but a regular file (left by a command run with sudo while the cable was missing) : sudo rm ${DEV}, then unplug and plug the cable"
fi
[ -c "${DEV}" ] || error "${DEV} not found : cable plugged ? given to the virtual machine ? (ls /dev/ttyUSB*)"

# Port already used by another program (screen, socat, cat, OpenOCD)
if command -v fuser > /dev/null && fuser -s "${DEV}" 2> /dev/null
then
    error "${DEV} is already open (fuser -v ${DEV}) : close the other terminal / socat / capture first"
fi

# Access to the port : sudo when the user is not in its group
SUDO=""
if [ ! -r "${DEV}" ] || [ ! -w "${DEV}" ]
then
    echo "No read / write access to ${DEV} : screen runs with sudo"
    echo "(to avoid it, once : tools/udev/install.sh, then log out and in)"
    SUDO=sudo
fi

TITLE="PicoSoC UART ${DEV} ${BAUD}"
echo "${TITLE} : board switches S5 S6 = 00 ; quit screen : Ctrl-A, k, y"

if [ -n "${DISPLAY:-}" ] && command -v xterm > /dev/null
then
    # The window stays open after screen (an error message stays readable),
    # Enter closes it ; sudo asks its password in the window
    xterm -T "${TITLE}" -geometry 120x40 -sl 5000 \
          -e bash -c "${SUDO} screen ${DEV} ${BAUD}; echo; read -r -p 'screen ended, Enter to close'" &
else
    echo "No X display or no xterm : screen in this terminal"
    exec ${SUDO} screen "${DEV}" "${BAUD}"
fi
