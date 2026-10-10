SHELL := /usr/bin/env bash

.PHONY: test lint install uninstall verify doctor bench

test:
	bash tests/run-unit.sh

lint:
	bash tests/static.sh

install:
	bash scripts/install.sh

uninstall:
	bash scripts/uninstall.sh

verify:
	bash scripts/verify.sh

doctor:
	bash scripts/doctor.sh

bench:
	bash tests/bench.sh
