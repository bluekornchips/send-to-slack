VERSION      := $(shell cat VERSION 2>/dev/null || echo "Unavailable")
TARGET_VERSION ?= $(VERSION)
SYSTEM_PREFIX := /usr/local
TAG           ?= $(TARGET_VERSION)

TEST_FILES    := $(shell find tests concourse -name '*-tests.sh' -type f)
SHELL_FILES   := $(shell find . -name "*.sh" -type f)
BATS_COMMAND  := bats --timing --verbose-run

.PHONY: lint test test-smoke test-acceptance test-all test-in-docker \
        concourse-up concourse-down concourse-load-examples concourse-clean-restart

#################################################
# Lint
#################################################

lint:
	shellcheck --version >/dev/null 2>&1 || (echo "shellcheck is not installed" && exit 1)
	shellcheck $(SHELL_FILES)

#################################################
# Testing
#################################################

test:
	clear && $(BATS_COMMAND) $(TEST_FILES)

test-smoke:
	clear && RUN_SMOKE_TEST=true $(BATS_COMMAND) $(TEST_FILES) -f "smoke_test::"

test-acceptance:
	clear && RUN_ACCEPTANCE_TEST=true $(BATS_COMMAND) $(TEST_FILES) -f "acceptance::"

test-all:
	clear && RUN_SMOKE_TEST=true RUN_ACCEPTANCE_TEST=true $(BATS_COMMAND) $(TEST_FILES)

test-in-docker:
	clear && ./tests/run-tests-in-docker.sh --make "make test"

#################################################
# Concourse
#################################################

concourse-up:
	docker-compose -f concourse/server.yaml up -d

concourse-down:
	docker-compose -f concourse/server.yaml down

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
		$(MAKE) concourse-down && \
		$(MAKE) concourse-up && \
		./ci/build.sh

concourse-run-all-examples: concourse-clean-restart
		./ci/run-all-examples.sh
