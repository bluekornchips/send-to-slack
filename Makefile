########################################################
# Variables
########################################################

VERSION := $(shell cat VERSION 2>/dev/null || echo "Unavailable")
SYSTEM_PREFIX := /usr/local

########################################################
# Development Dependencies
########################################################

check-deps:
	@command -v bats >/dev/null 2>&1 || { echo "Error: bats is required but not installed" >&2; exit 1; }
	@command -v shfmt >/dev/null 2>&1 || { echo "Error: shfmt is required but not installed" >&2; exit 1; }
	@command -v shellcheck >/dev/null 2>&1 || { echo "Error: shellcheck is required but not installed" >&2; exit 1; }

check-runtime-deps:
	@command -v bash >/dev/null 2>&1 || { echo "Error: bash is required but not installed" >&2; exit 1; }
	@command -v jq >/dev/null 2>&1 || { echo "Error: jq is required but not installed" >&2; exit 1; }
	@command -v curl >/dev/null 2>&1 || { echo "Error: curl is required but not installed" >&2; exit 1; }

########################################################
# Testing
########################################################

test: check-deps
	clear && bats --timing --verbose-run \
		./concourse/resource-type/tests/*tests.sh \
		./tests/*-tests.sh \
		./tests/blocks/*tests.sh

test-smoke: check-deps
	clear && SMOKE_TEST=true bats --timing --verbose-run \
		./tests/smoke-tests.sh

test-acceptance: check-deps
	clear && ACCEPTANCE_TEST=true bats --timing --verbose-run \
		./tests/acceptance-tests.sh

test-all: check-deps
	clear && SMOKE_TEST=true ACCEPTANCE_TEST=true \
		bats --timing --verbose-run \
		./concourse/resource-type/tests/*tests.sh \
		./tests/*-tests.sh \
		./tests/blocks/*tests.sh \
		./tests/smoke-tests.sh \
		./tests/acceptance-tests.sh

test-in-docker: check-deps
	clear && ./tests/run-tests-in-docker.sh

########################################################
# Code Quality
########################################################

format: check-deps
	find . -name "*.sh" -type f -exec shfmt -w {} \;

lint: check-deps
	find . -name "*.sh" -type f -exec shellcheck {} \;

########################################################
# Installation
########################################################

install:
	@sudo ./install.sh $(SYSTEM_PREFIX)

uninstall:
	@sudo ./uninstall.sh $(SYSTEM_PREFIX)
########################################################
# Concourse CI
########################################################

check-docker-deps:
	@command -v docker-compose >/dev/null 2>&1 || { echo "Error: docker-compose is required but not installed" >&2; exit 1; }

concourse-up: check-docker-deps
	docker-compose -f concourse/server.yaml up -d

concourse-down: check-docker-deps
	docker-compose -f concourse/server.yaml down

concourse-load-examples:
	@for file in examples/*.yaml; do \
		pipeline=$$(basename "$$file" .yaml); \
		echo "Loading pipeline: $$pipeline from $$file"; \
		fly -t local set-pipeline -p "$$pipeline" -c "$$file" --non-interactive -v SLACK_BOT_USER_OAUTH_TOKEN=$$SLACK_BOT_USER_OAUTH_TOKEN || exit 1; \
	done

########################################################
# Development Tools
########################################################

check-docker:
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker is required but not installed" >&2; exit 1; }

ngrok-up: check-docker
	docker run --net=host -it -e NGROK_AUTHTOKEN=${NGROK_AUTHTOKEN} ngrok/ngrok http --url=${NGROK_URL} 3000

check-python-deps:
	@command -v python3 >/dev/null 2>&1 || { echo "Error: python3 is required but not installed" >&2; exit 1; }

python-server: check-python-deps
	cd python && \
	if [ ! -d .venv ]; then \
		python3 -m venv .venv; \
	fi && \
	.venv/bin/pip install flask requests || exit 1 && \
	.venv/bin/python server.py
