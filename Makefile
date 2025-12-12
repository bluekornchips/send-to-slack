VERSION := $(shell cat VERSION 2>/dev/null || echo "Unavailable")
TARGET_VERSION ?= $(VERSION)
SYSTEM_PREFIX := /usr/local

# Testing
test:
	clear && bats --timing --verbose-run \
		./concourse/resource-type/tests/*tests.sh \
		./tests/*-tests.sh \
		./tests/blocks/*tests.sh

test-smoke:
	clear && SMOKE_TEST=true bats --timing --verbose-run \
		./tests/smoke-tests.sh

test-acceptance:
	clear && ACCEPTANCE_TEST=true bats --timing --verbose-run \
		./tests/acceptance-tests.sh

test-all:
	clear && SMOKE_TEST=true ACCEPTANCE_TEST=true \
		bats --timing --verbose-run \
		./concourse/resource-type/tests/*tests.sh \
		./tests/*-tests.sh \
		./tests/blocks/*tests.sh

test-in-docker:
	clear && DOCKER_IMAGE_TAG=local MAKE_COMMAND="make test" ./tests/run-tests-in-docker.sh

# installation
install:
	@sudo ./install.sh $(SYSTEM_PREFIX)

uninstall:
	@sudo ./uninstall.sh $(SYSTEM_PREFIX)

# concourse
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
		fly -t local set-pipeline -p "$$pipeline" -c "$$file" --non-interactive \
			-v SLACK_BOT_USER_OAUTH_TOKEN=$$SLACK_BOT_USER_OAUTH_TOKEN \
			-v channel=$$CHANNEL \
			|| exit 1; \
	done

# dev tools, not for production
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
