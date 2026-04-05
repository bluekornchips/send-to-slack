VERSION := $(shell cat VERSION 2>/dev/null || echo "Unavailable")
TARGET_VERSION ?= $(VERSION)
SYSTEM_PREFIX := /usr/local

ngrok-up:
	@if [ -z "$${NGROK_URL}" ]; then \
		docker run --net=host -it -e NGROK_AUTHTOKEN="$${NGROK_AUTHTOKEN}" ngrok/ngrok http 3000; \
	else \
		docker run --net=host -it -e NGROK_AUTHTOKEN="$${NGROK_AUTHTOKEN}" ngrok/ngrok http --url="$${NGROK_URL}" 3000; \
	fi

check-python-deps:
	@command -v python3 >/dev/null 2>&1 || { echo "Error: python3 is required but not installed" >&2; exit 1; }

python-server: check-python-deps
	if [ ! -d .venv ]; then \
		python3 -m venv .venv; \
	fi && \
	.venv/bin/pip install -r requirements.txt || exit 1 && \
	.venv/bin/python server.py
