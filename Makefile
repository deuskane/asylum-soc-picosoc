#-----------------------------------------------------------------------------
# Auto-generate file
#-----------------------------------------------------------------------------

#=============================================================================
# Variables
#=============================================================================
SHELL    	 = /bin/bash

FILE_CORE 	?= OB8_GPIO.core
TARGET          ?= emu_ng_medium_c_identity

CORE_NAME       := $(shell grep name $(FILE_CORE) | head -n1 | tr -d ' ')

VENDOR		 = $(shell echo $(CORE_NAME) | cut -d':' -f2)
LIBRARY 	 = $(shell echo $(CORE_NAME) | cut -d':' -f3)
NAME		 = $(shell echo $(CORE_NAME) | cut -d':' -f4)
VERSION		 = $(shell echo $(CORE_NAME) | cut -d':' -f5)
VLNV		 = $(VENDOR):$(LIBRARY):$(NAME):$(VERSION)

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
	@echo "setup      : Execute Setup stage of fusesoc flow for specific target"
	@echo "build      : Execute Build stage of fusesoc flow for specific target"
	@echo "run        : Execute Run   stage of fusesoc flow for specific target"
	@echo "*          : Run command"
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
	fusesoc run --build-root $(PATH_BUILD) --$@ --target $(TARGET) $(VLNV)

.PHONY : setup build run

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
