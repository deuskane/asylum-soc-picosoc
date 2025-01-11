#-----------------------------------------------------------------------------
# Title      : Makefile
# Project    : OB8_GPIO
#-----------------------------------------------------------------------------
# File       : OB8_GPIO.vhd
# Author     : Mathieu Rosiere
#-----------------------------------------------------------------------------
# Description: Makefile to execute fusesoc & impulse
#-----------------------------------------------------------------------------
# Copyright (c) 2024
#-----------------------------------------------------------------------------
# Revisions  :
# Date        Version  Author   Description
# 2024-12-31  1.0      mrosiere	Created
#-----------------------------------------------------------------------------

#=============================================================================
# Variables
#=============================================================================
SHELL    	 = /bin/bash

FILE_CORE	?= OB8_GPIO.core
TARGET          ?= emu_ng_medium_c_identity
TOOL		?= nxmap

CORE_NAME       := $(shell grep name $(FILE_CORE) | head -n1 | tr -d ' ')

IP_VENDOR	 = $(shell echo $(CORE_NAME) | cut -d':' -f2)
IP_LIBRARY 	 = $(shell echo $(CORE_NAME) | cut -d':' -f3)
IP_NAME		 = $(shell echo $(CORE_NAME) | cut -d':' -f4)
IP_VERSION	 = $(shell echo $(CORE_NAME) | cut -d':' -f5)
VLNV		 = $(IP_VENDOR):$(IP_LIBRARY):$(IP_NAME):$(IP_VERSION)

TARGETS_SIM	:= $(shell fusesoc core-info $(VLNV) | grep sim_ | cut -d ':' -f1 | tr -d ' ')
TARGETS_EMU	:= $(shell fusesoc core-info $(VLNV) | grep emu_ | cut -d ':' -f1 | tr -d ' ')

PATH_BUILD	?= $(CURDIR)/build

#=============================================================================
# Rules
#=============================================================================

#--------------------------------------------------------
# Display list of target
help :
#--------------------------------------------------------
	@echo ""
	@echo ">>>>>>>  Makefile Help"
	@echo ""
	@echo "===========| Variables"
	@echo "VLNV       : Vendor/Library/Name/Version"
	@echo "             $(VLNV)"
	@echo "TARGET     : Specific Target for Fusesoc"
	@echo "             $(TARGET)"
	@echo "TOOL       : Specific Tool for Fusesoc"
	@echo "             $(TOOL)"
	@echo "TARGET_SIM : All simulation targets"
	@echo "             $(TARGETS_SIM)"
	@echo "TARGET_EMU : All emulation targets"
	@echo "             $(TARGETS_EMU)"
	@echo "PATH_BUILD : Path to build directory"
	@echo "             $(PATH_BUILD)"
	@echo ""
	@echo "===========| Rules"
	@echo "help       : Print this message"
	@echo "info       : Display library list and cores list"
	@echo "nonreg     : Run all simulation targets"
	@echo "setup      : Execute Setup stage of fusesoc flow for specific target and tool"
	@echo "build      : Execute Build stage of fusesoc flow for specific target and tool"
	@echo "run        : Execute Run   stage of fusesoc flow for specific target and tool"
	@echo "impulse    : Execute the specific target in gui, Warning, the target must be previously build"
	@echo "*          : Run target with default tool"
	@echo "clean      : delete build directory"
	@echo ""
	@echo ">>>>>>>  Core Information"
	@echo ""
	@fusesoc core-info $(VLNV)

.PHONY  : help

#--------------------------------------------------------
# Display library list and cores list
info :
#--------------------------------------------------------
	@fusesoc library list
	@fusesoc list-cores

.PHONY : info

#--------------------------------------------------------
setup build run :
#--------------------------------------------------------
	fusesoc run --build-root $(PATH_BUILD) --$@ --target $(TARGET) --tool $(TOOL) $(VLNV)

.PHONY : setup build run

#--------------------------------------------------------
impulse :
#--------------------------------------------------------
	(cd $(PATH_BUILD)/$(TARGET)-$(TOOL)/work; ${IMPULSE} $(NAME)_native.nym)

#--------------------------------------------------------
% :
#--------------------------------------------------------
	@fusesoc run --build-root $(PATH_BUILD) --target $* $(VLNV)

#--------------------------------------------------------
nonreg : \
	$(TARGETS_SIM)
#--------------------------------------------------------
# nothing

.PHONY : nonreg

#--------------------------------------------------------
clean :
#--------------------------------------------------------
	rm -fr $(PATH_BUILD)

.PHONY : clean
