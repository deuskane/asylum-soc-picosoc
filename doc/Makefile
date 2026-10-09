#===================================================================
# Variables
#===================================================================
# Configuration
DRAWIO_APP          = drawio
SCALE               = 2
FORMAT              = png

SOURCES             = $(wildcard *.drawio)

RULE_IMAGE_TARGETS := $(shell \
	for f in $(SOURCES); do \
		base=$$(basename $$f .drawio); \
		grep -o 'name="[^"]*"' "$$f" | sed 's/name="//;s/"//' | \
		( \
		idx=1; \
		while read name; do \
			echo "$${f}#$${idx}#$${base}-$${name}.$(FORMAT)"; \
			idx=$$(($${idx}+1)); \
		done; \
		); \
		rm -f "$$f.xml"; \
	done \
)

#===================================================================
# Target
#===================================================================
.DEFAULT_GOAL       = all

#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
define GEN_RULE
#~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# 1 : source file
# 2 : dest file
# 3 : page indexe

IMAGE_TARGETS += $(2)

#-------------------------------------------------------------------
$(2): $(1)
#-------------------------------------------------------------------
	$(DRAWIO_APP) --export --format $(FORMAT) --scale $(SCALE) --page-index $(3) --crop --output "$(2)" "$(1)"
endef

$(foreach tgt,$(RULE_IMAGE_TARGETS),$(eval $(call GEN_RULE,$(shell echo "$(tgt)" | cut -d'#' -f1),$(shell echo "$(tgt)" | cut -d'#' -f3),$(shell echo "$(tgt)" | cut -d'#' -f2))))

#-------------------------------------------------------------------
all: $(IMAGE_TARGETS)
#-------------------------------------------------------------------
	@echo "--- Toutes les images sont à jour ---"

.PHONY: all

#-------------------------------------------------------------------
clean:
#-------------------------------------------------------------------
	rm $(IMAGE_TARGETS)

.PHONY: clean
