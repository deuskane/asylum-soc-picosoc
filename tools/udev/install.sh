#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# Title      : Installation of the udev rules of the PicoSoC cables
# Project    : PicoSoC
#-----------------------------------------------------------------------------
# File       : install.sh
# Author     : mrosiere
#-----------------------------------------------------------------------------
# Description: Gives the FTDI cables of the board (USB device for OpenOCD,
#              serial port for screen / socat / the HWLA captures) to the
#              group dialout, without sudo, once and for all :
#                tools/udev/install.sh             : install (asks the sudo
#                                                    password)
#                tools/udev/install.sh --uninstall : remove the rules
#              Steps : 60-picosoc.rules copied to /etc/udev/rules.d, udev
#              rules reloaded and applied to the cables already plugged,
#              the user added to the group dialout (to log out and in once
#              to get it), then the access of the plugged cables shown.
#-----------------------------------------------------------------------------
# Copyright (c) 2026
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2026-11-27  1.0      mrosiere Created
#-----------------------------------------------------------------------------

set -euo pipefail

DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RULES=60-picosoc.rules
DEST=/etc/udev/rules.d/${RULES}

command -v udevadm > /dev/null || { echo "Error : udevadm not found (no udev on this host ?)" >&2; exit 1; }

reload()
{
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=usb --subsystem-match=tty
}

case "${1:-}" in
    -h|--help)
        sed -n '/^# Description:/,/^#----/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; /^---/d'
        exit 0 ;;
    --uninstall)
        sudo rm -f "${DEST}"
        reload
        echo "${DEST} removed"
        exit 0 ;;
    "") ;;
    *)
        echo "Usage : $0 [--uninstall]" >&2
        exit 1 ;;
esac

# Rules
sudo install -m 0644 "${DIR}/${RULES}" "${DEST}"
reload
echo "${DEST} installed"

# Group of the user
if id -nG "${USER}" | tr ' ' '\n' | grep -qx dialout
then
    echo "${USER} is in the group dialout"
else
    sudo usermod -aG dialout "${USER}"
    echo "${USER} added to the group dialout : log out and in (or reboot the virtual machine) once to get it"
fi

# Cables plugged now (no error if none)
sleep 1
found=0
for vp in 0403:6001 0403:6010 0403:6014
do
    while read -r _ bus _ dev _
    do
        [ -n "${bus:-}" ] || continue
        found=1
        ls -l "/dev/bus/usb/${bus}/${dev%:}"
    done < <(lsusb -d "${vp}" 2> /dev/null || true)
done
ls -l /dev/ttyUSB* 2> /dev/null || true
if [ "${found}" -eq 0 ]
then
    echo "No FTDI cable plugged now : the rules apply when it is plugged"
else
    echo "Expected : group dialout, crw-rw---- (else unplug and plug the cable)"
fi
