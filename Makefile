# Swarm Agent Coordination — kit checks and corpus analysis.
#
#   make check      everything: kit self-test + corpus analysis
#   make verify     the kit's own scripts, against throwaway repos (38 checks)
#   make reproduce  recompute the published numbers from the corpus
#   make classify   re-derive incidents -> data/incidents.json
#
# The analysis targets need export/, which is not in this repository and is
# refused by .gitignore — see analysis/README.md. They say so and exit 0 rather
# than failing, so `make check` stays useful for anyone who only has the kit.

EXPORT ?= export
PYTHON ?= python3

.PHONY: check verify reproduce classify clean help

help:
	@sed -n 's/^#   //p' $(MAKEFILE_LIST)

check: verify reproduce classify

verify:
	@sh verify-kit.sh

SKIP_MSG = no corpus at $(EXPORT)/ — analysis skipped. \
	   See analysis/README.md: the corpus is not published with this repo.

reproduce:
	@if [ -d "$(EXPORT)" ]; then $(PYTHON) analysis/reproduce.py --export "$(EXPORT)"; \
	 else echo "$(SKIP_MSG)"; fi

classify:
	@if [ -d "$(EXPORT)" ]; then $(PYTHON) analysis/classify.py --export "$(EXPORT)"; \
	 else echo "$(SKIP_MSG)"; fi

clean:
	@rm -f data/incidents.json
	@echo "removed derived output; the corpus and the scripts are untouched"
