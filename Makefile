# Swarm Agent Coordination — kit checks and corpus analysis.
#
#   make check      everything: kit self-test + corpus analysis
#   make verify     the kit's own scripts and experiments, against throwaway repos (58 checks)
#   make reproduce  recompute the published numbers from the corpus
#   make classify   re-derive incidents -> data/incidents.json
#   make audit      swarm-audit unit tests, and score its codebook on the corpus
#
# The analysis targets need export/, which is not in this repository and is
# refused by .gitignore — see analysis/README.md. They say so and exit 0 rather
# than failing, so `make check` stays useful for anyone who only has the kit.

EXPORT ?= export
PYTHON ?= python3
NODE   ?= node

.PHONY: check verify reproduce classify audit audit-test audit-codebook clean help

help:
	@sed -n 's/^#   //p' $(MAKEFILE_LIST)

check: verify reproduce classify audit

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

audit: audit-test audit-codebook

audit-test:
	@cd packages/swarm-audit && npm test

audit-codebook:
	@if [ -d "$(EXPORT)" ]; then $(NODE) packages/swarm-audit/tools/corpus-check.mjs --export "$(EXPORT)"; \
	 else echo "$(SKIP_MSG)"; fi

clean:
	@rm -f data/incidents.json
	@echo "removed derived output; the corpus and the scripts are untouched"
