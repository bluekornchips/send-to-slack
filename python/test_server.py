import hashlib
import hmac
import importlib
import json
import os
import time
import unittest
import urllib.parse

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

    def _post(
        self,
        body,
        *,
        content_type="application/json",
        secret=None,
        good_sig=True,
        headers=None,
    ):
        if not isinstance(body, str):
            body = json.dumps(body)
        timestamp = int(time.time())
        use_secret = secret if secret is not None else os.environ["SLACK_SIGNING_SECRET"]
        header_sig = sign_body(use_secret, timestamp, body) if good_sig else "v0=bad"
        request_headers = {
            "X-Slack-Request-Timestamp": str(timestamp),
            "X-Slack-Signature": header_sig,
            "Content-Type": content_type,
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
        response = self.client.post(
            "/slack/actions",
            data=json.dumps(payload),
            headers={"Content-Type": "application/json"},
        )
        self.assertEqual(response.status_code, 401)

    def test_accepts_valid_signature(self):
        payload = {"actions": [{"action_id": "test_action"}], "channel": {"id": "C1"}, "user": {"id": "U1"}}
        self.server.send_slack_message = lambda channel_id, text: None
        response = self._post(payload, good_sig=True)
        self.assertEqual(response.status_code, 200)

    def test_accepts_form_encoded_payload(self):
        payload = {"actions": [{"action_id": "test_action"}], "channel": {"id": "C1"}, "user": {"id": "U1"}}
        body = urllib.parse.urlencode({"payload": json.dumps(payload)})
        seen = {}

        def capture(channel_id, text):
            seen["channel_id"] = channel_id

        self.server.send_slack_message = capture
        response = self._post(body, content_type="application/x-www-form-urlencoded")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(seen["channel_id"], "C1")

    def test_routes_send_user_message_to_user_id(self):
        payload = {"actions": [{"action_id": "send_user_message"}], "channel": {"id": "C1"}, "user": {"id": "U1"}}
        seen = {}

        def capture(channel_id, text):
            seen["channel_id"] = channel_id

        self.server.send_slack_message = capture
        response = self._post(payload)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(seen["channel_id"], "U1")

