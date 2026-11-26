#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# Title      : OpenOCD on the PicoSoC board
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : openocd.sh
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Checks the host, then runs OpenOCD with an adapter file and a
#              chain file of this directory :
#                tools/openocd/openocd.sh <adapter> [chain] [openocd options]
#              adapter : ft232r          FT232R cable, mode 10 (S5 S6 = 10)
#                        ft232h          FTDI MPSSE cable, mode 10
#                        remote_bitbang  JTAG over the UART, mode 11
#                                        (S5 S6 = 11, after
#                                        remote_bitbang_setup.sh)
#              chain   : picosoc (default : riscv targets, GDB from port
#                        3333, telnet 4444) or discover (prints the chain
#                        and exits)
#              The other arguments go to OpenOCD (e.g. -d3, or
#              -c "set picosoc_chain {...}" with the chain picosoc).
#              Checks : OpenOCD >= 0.11, the cable on USB (ft232r / ft232h,
#              lsusb) and its access (sudo otherwise), the serial port free
#              (ft232r), the TCP port of remote_bitbang open, the GDB /
#              telnet / TCL ports free.
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-26  1.0      mrosiere Created
#-----------------------------------------------------------------------------

set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

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

warning()
{
    echo "Warning : $*" >&2
}

[ $# -ge 1 ] || usage 1
case "$1" in
    -h|--help) usage 0 ;;
esac

ADAPTER=$1 ; shift
CHAIN=picosoc
if [ $# -ge 1 ] && { [ "$1" = picosoc ] || [ "$1" = discover ]; }
then
    CHAIN=$1 ; shift
fi

case "${ADAPTER}" in
    ft232r)         VID_PID=0403:6001 ; MODE="10 (S5 = 1, S6 = 0)" ;;
    ft232h)         VID_PID=0403:6014 ; MODE="10 (S5 = 1, S6 = 0)" ;;
    remote_bitbang) VID_PID=""        ; MODE="11 (S5 = 1, S6 = 1)" ;;
    *)              error "unknown adapter '${ADAPTER}' (ft232r, ft232h or remote_bitbang)" ;;
esac

ADAPTER_CFG=${DIR}/${ADAPTER}.cfg
CHAIN_CFG=${DIR}/${CHAIN}.cfg
[ -f "${ADAPTER_CFG}" ] || error "${ADAPTER_CFG} not found"
[ -f "${CHAIN_CFG}"   ] || error "${CHAIN_CFG} not found"

#--------------------------------------
# OpenOCD >= 0.11 (ft232r driver, RISC-V debug)
#--------------------------------------
OPENOCD=${OPENOCD:-openocd}
command -v "${OPENOCD}" > /dev/null || error "${OPENOCD} not found : install OpenOCD >= 0.11 (CentOS 8 : xPack OpenOCD 0.12), or set OPENOCD=<path of openocd>"
# Full path : sudo does not search the PATH of the user
OPENOCD=$(command -v "${OPENOCD}")
VERSION=$("${OPENOCD}" --version 2>&1 | head -n 1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+' | head -n 1 || true)
if [ -z "${VERSION}" ]
then
    warning "version of ${OPENOCD} not found, >= 0.11 expected"
else
    MAJOR=${VERSION%%.*}
    MINOR=${VERSION#*.} ; MINOR=${MINOR%%.*}
    if [ "${MAJOR}" -eq 0 ] && [ "${MINOR}" -lt 11 ]
    then
        error "OpenOCD ${VERSION} : >= 0.11 needed (ft232r driver, RISC-V debug)"
    fi
fi

#--------------------------------------
# Ports of OpenOCD free (another OpenOCD still running ?)
#--------------------------------------
port_listen()
{
    if command -v ss > /dev/null
    then
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -q "[:.]$1\$"
    else
        (exec 3<> "/dev/tcp/127.0.0.1/$1") 2> /dev/null
    fi
}

for port in 3333 4444 6666
do
    if port_listen "${port}"
    then
        error "TCP port ${port} already used : another OpenOCD running ? (pkill openocd)"
    fi
done

#--------------------------------------
# Adapter
#--------------------------------------
SUDO=""
if [ -n "${VID_PID}" ]
then
    # USB cable present
    if command -v lsusb > /dev/null
    then
        USB=$(lsusb -d "${VID_PID}" 2>/dev/null | head -n 1 || true)
        [ -n "${USB}" ] || error "no USB device ${VID_PID} (${ADAPTER} cable) : plugged ? given to the virtual machine (VirtualBox : Devices > USB) ?"
        BUS=$(echo "${USB}" | awk '{print $2}')
        DEVNUM=$(echo "${USB}" | awk '{print $4}' | tr -d ':')
        NODE=/dev/bus/usb/${BUS}/${DEVNUM}
        if [ -e "${NODE}" ] && { [ ! -r "${NODE}" ] || [ ! -w "${NODE}" ]; }
        then
            echo "No access to the USB device ${NODE} : OpenOCD runs with sudo"
            echo "(to avoid it : the udev rules of OpenOCD, contrib/60-openocd.rules, in /etc/udev/rules.d, then unplug and plug the cable)"
            SUDO=sudo
        fi
    else
        warning "lsusb not found : the ${ADAPTER} cable is not checked"
    fi

    # The serial port of an FT232R must be free (no terminal on it)
    if [ "${ADAPTER}" = ft232r ] && command -v fuser > /dev/null
    then
        for tty in /dev/ttyUSB*
        do
            [ -c "${tty}" ] || continue
            if fuser -s "${tty}" 2> /dev/null
            then
                warning "${tty} is open (screen, socat ?) : close it, OpenOCD takes the cable"
            fi
        done
    fi
else
    # JTAG over the UART : remote_bitbang_setup.sh must listen on 9824
    port_listen 9824 || error "nothing on TCP port 9824 : run first tools/openocd/remote_bitbang_setup.sh /dev/ttyUSB0 <JTAG_BAUD_RATE> in another terminal"
fi

#--------------------------------------
# Run
#--------------------------------------
echo "Board  : mode ${MODE}, bitstream with at least one TAP"
echo "OpenOCD: ${OPENOCD} -f ${ADAPTER_CFG} -f ${CHAIN_CFG} $*"
if [ "${CHAIN}" = picosoc ]
then
    echo "Then   : GDB on localhost:3333 (and the next ports), telnet localhost 4444"
fi

exec ${SUDO} "${OPENOCD}" -f "${ADAPTER_CFG}" -f "${CHAIN_CFG}" "$@"
