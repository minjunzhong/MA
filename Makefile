PYTHON ?= python3

.PHONY: test lint all

test:
	$(PYTHON) scripts/test_stage3.py

lint:
	$(PYTHON) scripts/test_stage3.py --lint-only

all:
	$(PYTHON) scripts/test_stage3.py --lint
