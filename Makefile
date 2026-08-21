VERSION        := $(shell cat VERSION 2>/dev/null || echo "Unavailable")
TARGET_VERSION ?= $(VERSION)
SYSTEM_PREFIX  := /usr/local
TAG            ?= $(TARGET_VERSION)

TEST_FILES     := $(shell find tests concourse -name '*-tests.sh' -type f \
	! -name 'smoke-tests.sh' ! -name 'acceptance-tests.sh')
SHELL_FILES    := $(shell find . -name "*.sh" -type f)
BATS_JOBS      ?= $(shell nproc 2>/dev/null || echo 4)
BATS_FLAGS     := --timing --verbose-run --formatter pretty

.PHONY: lint test test-serial test-smoke test-acceptance test-all test-in-docker \
        concourse-start concourse-stop concourse-stop-clean concourse-load-examples \
        concourse-clean-restart concourse-run-all-examples

.DEFAULT_GOAL := ci

#################################################
# Lint
#################################################

lint:
	@command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck is not installed" >&2; exit 1; }
	@echo "lint: shellcheck $$(echo $(SHELL_FILES) | wc -w) files"
	@shellcheck $(SHELL_FILES)
	@echo "lint: shellcheck ok"

#################################################
# Testing
#################################################

test:
	@bats $(BATS_FLAGS) --jobs $(BATS_JOBS) --no-parallelize-within-files $(TEST_FILES)

test-serial:
	@bats $(BATS_FLAGS) $(TEST_FILES)

test-smoke:
	@RUN_SMOKE_TEST=true bats $(BATS_FLAGS) tests/smoke-tests.sh

test-acceptance:
	@RUN_ACCEPTANCE_TEST=true bats $(BATS_FLAGS) tests/acceptance-tests.sh

test-all: test test-smoke test-acceptance

test-in-docker:
	@./tests/run-tests-in-docker.sh --make "make test-serial BATS_FLAGS='--timing --verbose-run --formatter tap'"

#################################################
# Concourse
#################################################

concourse-start:
	docker-compose -f concourse/server.yaml up -d

concourse-stop:
	docker-compose -f concourse/server.yaml down -v --remove-orphans

concourse-load-examples:
	@for file in examples/*.yaml; do \
		pipeline=$$(basename "$$file" .yaml); \
		echo "Loading pipeline: $$pipeline from $$file"; \
		fly -t local set-pipeline -p "$$pipeline" -c "$$file" --non-interactive \
			-v "SLACK_BOT_USER_OAUTH_TOKEN=$$SLACK_BOT_USER_OAUTH_TOKEN" \
			-v "channel=$$CHANNEL" \
			-v "side_channel=$$SIDE_CHANNEL" \
			-v "SLACK_WEBHOOK_URL=$$SLACK_WEBHOOK_URL" \
			-v "ephemeral_user=$$EPHEMERAL_USER" \
			-v "TAG=$(TAG)" \
			|| exit 1; \
	done

concourse-clean-restart:
	clear && \
		$(MAKE) concourse-stop && \
		$(MAKE) concourse-start && \
		./ci/build.sh

concourse-run-all-examples: concourse-clean-restart
		./ci/run-all-examples.sh

ci: lint test
