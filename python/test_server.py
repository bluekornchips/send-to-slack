import hashlib
import hmac
import importlib
import json
import os
import time
import unittest
from typing import Any

import server as server_module


def sign_body(secret: str, timestamp: int, body: str) -> str:
    base = f"v0:{timestamp}:{body}".encode()
    digest = hmac.new(secret.encode(), base, hashlib.sha256).hexdigest()
    return f"v0={digest}"


class SlackSignatureTests(unittest.TestCase):
    def setUp(self) -> None:
        os.environ["SLACK_BOT_USER_OAUTH_TOKEN"] = "test-token"
        os.environ["SLACK_SIGNING_SECRET"] = "test-secret"
        os.environ["DEFAULT_ACTION_MESSAGE"] = "Hello"
        self.server = importlib.reload(server_module)
        self.client = self.server.app.test_client()

    def _post(self, body_dict: Any, secret: str | None = None, good_sig: bool = True, headers: dict[str, str] | None = None):
        body = json.dumps(body_dict)
        timestamp = int(time.time())
        header_sig = ""
        use_secret = secret if secret is not None else os.environ["SLACK_SIGNING_SECRET"]
        if good_sig:
            header_sig = sign_body(use_secret, timestamp, body)
        else:
            header_sig = "v0=bad"
        request_headers = {
            "X-Slack-Request-Timestamp": str(timestamp),
            "X-Slack-Signature": header_sig,
            "Content-Type": "application/json",
        }
        if headers:
            request_headers.update(headers)
        return self.client.post("/slack/actions", data=body, headers=request_headers)

    def test_rejects_invalid_signature(self):
        payload = {"actions": [{"action_id": "test_action"}], "channel": {"id": "C1"}, "user": {"id": "U1"}}
        response = self._post(payload, good_sig=False)
        self.assertEqual(response.status_code, 401)

    def test_rejects_missing_signature_headers(self):
        payload = {"actions": [{"action_id": "test_action"}], "channel": {"id": "C1"}, "user": {"id": "U1"}}
        response = self.client.post("/slack/actions", data=json.dumps(payload), headers={"Content-Type": "application/json"})
        self.assertEqual(response.status_code, 401)

    def test_accepts_valid_signature(self):
        payload = {"actions": [{"action_id": "test_action"}], "channel": {"id": "C1"}, "user": {"id": "U1"}}
        self.server.send_slack_message = lambda channel_id, text: None
        response = self._post(payload, good_sig=True)
        self.assertEqual(response.status_code, 200)




