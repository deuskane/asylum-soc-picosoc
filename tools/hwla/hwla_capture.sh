#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# Title      : Capture of the HWLA of the PicoSoC board on the UART
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : hwla_capture.sh
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Saves the bytes of the HWLA captures received on the serial
#              port in a binary file, and shows the number of bytes and of
#              complete captures as they arrive :
#                tools/hwla/hwla_capture.sh [-d device] [-b baud] [-o file]
#                                           [-s bytes] [-n captures]
#                -d : serial port (default /dev/ttyUSB0)
#                -b : HWLA_BAUD_RATE of the bitstream (default 9600, the
#                     NG-MEDIUM targets)
#                -o : output file (default capture.bin, appended : remove it
#                     for a new capture)
#                -s : bytes of a capture (default 12288 : HWLA_DEPTH 1024
#                     samples x 12 bytes, WardRV_fsm with the 16-bit
#                     timestamp, the NG-MEDIUM targets ; OpenBlaze8 :
#                     1024 x 10 = 10240)
#                -n : stop after this number of complete captures (default 0 :
#                     Ctrl-C to stop)
#              Board : switches S5 S6 = 01 (UART of the HWLA on the UART pads,
#              TP2 pin 3), or the cable RXD on debug_uart_tx_o (TP2 pin 7) in
#              any mode ; a capture is sent when the HWLA triggers (difference
#              of the lock-step / TMR CPUs, e.g. push button S8).
#              Then : hwla/hwla2vcd.py and hwla/hwla_<cpu>.args in the build
#              directory of the target of the bitstream (README, HWLA
#              section).
#              Checks as tools/uart/uart.sh (serial port, port free, sudo).
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-27  1.0      mrosiere Created
# 2026-11-27  1.1      mrosiere Hint : hwla/hwla2vcd.py and hwla/hwla_<cpu>.args
#                               of the build directory of the target
# 2026-11-27  1.2      mrosiere Default size 12288 (HWLA_DEPTH 1024 of the
#                               NG-MEDIUM targets, 74 probes of WardRV_fsm)
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

DEV=/dev/ttyUSB0
BAUD=9600
OUT=capture.bin
SIZE=12288
NB=0
while getopts "d:b:o:s:n:h" opt
do
    case "${opt}" in
        d) DEV=${OPTARG} ;;
        b) BAUD=${OPTARG} ;;
        o) OUT=${OPTARG} ;;
        s) SIZE=${OPTARG} ;;
        n) NB=${OPTARG} ;;
        h) usage 0 ;;
        *) usage 1 ;;
    esac
done

if [ -e "${DEV}" ] && [ ! -c "${DEV}" ]
then
    error "${DEV} is not a serial port but a regular file (left by a command run with sudo while the cable was missing) : sudo rm ${DEV}, then unplug and plug the cable"
fi
[ -c "${DEV}" ] || error "${DEV} not found : cable plugged ? given to the virtual machine ? (ls /dev/ttyUSB*)"
if command -v fuser > /dev/null && fuser -s "${DEV}" 2> /dev/null
then
    error "${DEV} is already open (fuser -v ${DEV}) : close the terminal (screen) or the other capture first"
fi

SUDO=""
if [ ! -r "${DEV}" ] || [ ! -w "${DEV}" ]
then
    echo "No read / write access to ${DEV} : stty and cat run with sudo"
    echo "(to avoid it, once : tools/udev/install.sh, then log out and in)"
    SUDO=sudo
    sudo -v    # password asked now, not by the reader in the background
fi

# Raw bytes, 8N1, no flow control
${SUDO} stty -F "${DEV}" "${BAUD}" raw -echo -echoe -echok -echoctl -echoke \
        cs8 -cstopb -parenb -crtscts -ixon -ixoff -hupcl clocal

touch "${OUT}"
START=$(stat -c %s "${OUT}")

# Reader in the background : the redirection is made by this shell, so the
# file belongs to the user even when cat runs with sudo
${SUDO} cat "${DEV}" >> "${OUT}" &
READER=$!

stop()
{
    ${SUDO} kill "${READER}" 2> /dev/null || true
    wait "${READER}" 2> /dev/null || true
}
trap stop EXIT
STOP=""
trap 'STOP=1' INT TERM    # Ctrl-C : end of the loop, then the summary

echo "HWLA capture : ${DEV} at ${BAUD} baud -> ${OUT} (${SIZE} bytes per capture), board switches S5 S6 = 01"
echo "Trigger the HWLA (e.g. push button S8) ; Ctrl-C to stop"

LAST=-1
while [ -z "${STOP}" ] && ps -p "${READER}" > /dev/null
do
    BYTES=$(( $(stat -c %s "${OUT}") - START ))
    if [ "${BYTES}" -ne "${LAST}" ]
    then
        printf "\r%8d bytes, %d complete capture(s), %d bytes of the next one   " \
               "${BYTES}" $(( BYTES / SIZE )) $(( BYTES % SIZE ))
        LAST=${BYTES}
    fi
    if [ "${NB}" -gt 0 ] && [ $(( BYTES / SIZE )) -ge "${NB}" ]
    then
        break
    fi
    sleep 0.2 || true
done
echo
echo "${OUT} : $(( $(stat -c %s "${OUT}") - START )) bytes received"
echo "VCD : H=build/asylum_soc_PicoSoC_<version>/<target>-nxmap/hwla   (build directory of the bitstream)"
echo "      python3 \${H}/hwla2vcd.py ${OUT} --args-file \${H}/hwla_wardrv_fsm.args -o capture.vcd"
echo "      (several captures : --merge, all in one VCD file ; OpenBlaze8 : hwla_openblaze8.args ;"
echo "       another HWLA configuration : its -d, -p, -t, --period lines ; README, HWLA section)"
