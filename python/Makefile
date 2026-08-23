.PHONY: venv test check python-server ngrok-up clean

PYTHON ?= python3
VENV := .venv

venv:
	@test -d $(VENV) || $(PYTHON) -m venv $(VENV)
	@$(VENV)/bin/pip install -q -r requirements.txt

test: venv
	@$(VENV)/bin/python -m unittest test_server.py -v

check: venv
	@$(VENV)/bin/pip install -q ruff
	@$(VENV)/bin/ruff check .
	@$(MAKE) test

python-server: venv
	@$(VENV)/bin/python server.py

ngrok-up:
	@if [ -z "$${NGROK_URL}" ]; then \
		docker run --net=host -it -e NGROK_AUTHTOKEN="$${NGROK_AUTHTOKEN}" ngrok/ngrok http 3000; \
	else \
		docker run --net=host -it -e NGROK_AUTHTOKEN="$${NGROK_AUTHTOKEN}" ngrok/ngrok http --url="$${NGROK_URL}" 3000; \
	fi

clean:
	rm -rf $(VENV)
