#-----------------------------------------------------------------------------
# Auto-generate file
#-----------------------------------------------------------------------------

#=============================================================================
# Variables
#=============================================================================
SHELL      = /bin/bash
FILE_CORE  = OB8_GPIO.core
CORE      ?= $(shell grep name $(FILE_CORE) | head -n1| cut -d' ' -f3)
include mk/targets.mk

#=============================================================================
# Rules
#=============================================================================

help    :
	@echo "=========| Variables"
	@echo "CORE     : $(CORE)"
	@echo ""
	@echo "=========| Rules"
	@echo "help     : Print this message"
	@echo "run      : run all targets"
	@echo "run_%    : run one target"
	@echo "clean    : delete build directory"
	@echo ""
	@echo "=========| Targets"
	@for target in $(TARGETS); do echo $${target}; done

.PHONY  : list

run	: $(addprefix run_,$(TARGETS))

.PHONY	: run

run_%	:
	@echo "[$*]"
	fusesoc run --build-root build-$* --run --target $* $(CORE)

.PHONY	: run_%


clean	:
	rm -fr build build-*

.PHONY	: clean
