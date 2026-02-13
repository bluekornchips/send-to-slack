#!/usr/bin/env python3

import hashlib
import hmac
import json
import logging
import os
import time
import urllib.parse
from typing import Any, Dict, Optional

import requests
from flask import Flask, Response, Request, request

LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO').upper()
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO))
logger = logging.getLogger(__name__)

app = Flask(__name__)

PORT = int(os.getenv('PORT', '3000'))
SLACK_BOT_TOKEN = os.getenv('SLACK_BOT_USER_OAUTH_TOKEN', '')
SLACK_SIGNING_SECRET = os.getenv('SLACK_SIGNING_SECRET', '')
DEFAULT_BIND_HOST = os.getenv('BIND_HOST', '127.0.0.1')
DEFAULT_MESSAGE = os.getenv('DEFAULT_ACTION_MESSAGE', 'Hello, world!')


def send_slack_message(channel_id: str, text: str) -> None:
    """Send a simple text message to a Slack channel or user."""
    if not channel_id or not text or not SLACK_BOT_TOKEN:
        raise ValueError('Missing required parameters')

    payload = {'channel': channel_id, 'text': text}
    if logger.isEnabledFor(logging.DEBUG):
        logger.debug('Slack API request: channel=%s text_len=%d', channel_id, len(text))

    response = requests.post(
        'https://slack.com/api/chat.postMessage',
        headers={
            'Authorization': f'Bearer {SLACK_BOT_TOKEN}',
            'Content-Type': 'application/json',
        },
        json=payload,
        timeout=30,
    )

    response.raise_for_status()
    data = response.json()

    if logger.isEnabledFor(logging.DEBUG):
        logger.debug('Slack API response: ok=%s ts=%s', data.get('ok'), data.get('ts'))

    if not data.get('ok'):
        raise RuntimeError(f'Slack API error: {data.get("error")}')


def parse_payload() -> Dict[str, Any]:
    """Parse Slack action payload, handling form-encoded or raw JSON bodies."""
    body = request.get_data(as_text=True)
    if not body:
        raise ValueError('Payload is required')
    
    if 'payload=' in body:
        params = urllib.parse.parse_qs(body)
        encoded = params.get('payload', [None])[0]
        if encoded:
            return json.loads(urllib.parse.unquote_plus(encoded))
    
    return json.loads(body) if isinstance(body, str) else body


def _verify_slack_signature(req: Request) -> bool:
    """Validate Slack request signature and timestamp to prevent spoofing and replay."""
    if not SLACK_SIGNING_SECRET:
        logger.error('SLACK_SIGNING_SECRET is required to verify requests')
        return False

    timestamp = req.headers.get('X-Slack-Request-Timestamp', '')
    signature = req.headers.get('X-Slack-Signature', '')
    if not timestamp or not signature:
        return False

    try:
        timestamp_int = int(timestamp)
    except ValueError:
        return False

    if abs(time.time() - timestamp_int) > 300:
        return False

    payload = f'v0:{timestamp}:{req.get_data(as_text=True)}'.encode()
    expected = 'v0=' + hmac.new(
        SLACK_SIGNING_SECRET.encode(),
        payload,
        hashlib.sha256,
    ).hexdigest()

    return hmac.compare_digest(expected, signature)


@app.before_request
def require_valid_slack_signature() -> Optional[Response]:
    """Reject Slack action requests that fail signature verification."""
    if request.path != '/slack/actions':
        return None

    if not _verify_slack_signature(request):
        return Response('invalid signature', status=401)

    return None


def _payload_debug_summary(payload: Dict[str, Any]) -> Dict[str, Any]:
    """Extract non-sensitive fields for debug logging."""
    return {
        'action_id': (payload.get('actions') or [{}])[0].get('action_id'),
        'user_id': payload.get('user', {}).get('id'),
        'channel_id': payload.get('channel', {}).get('id'),
        'trigger_id': payload.get('trigger_id', '')[:20] + '...' if payload.get('trigger_id') else None,
    }


@app.route('/slack/actions', methods=['POST'])
def handle_actions():
    try:
        payload = parse_payload()
        if logger.isEnabledFor(logging.DEBUG):
            logger.debug('Incoming payload summary: %s', _payload_debug_summary(payload))

        actions = payload.get('actions', [])
        action_id = actions[0].get('action_id') if actions else None

        if not action_id:
            return Response('Missing action_id', status=400)

        user_id = payload.get('user', {}).get('id')
        channel_id = payload.get('channel', {}).get('id')

        if action_id == 'send_channel_message':
            send_slack_message(channel_id, DEFAULT_MESSAGE)
        elif action_id == 'send_user_message':
            send_slack_message(user_id, DEFAULT_MESSAGE)
        elif action_id == 'test_action':
            send_slack_message(channel_id, DEFAULT_MESSAGE)
        else:
            return Response(f'Unknown action_id: {action_id}', status=400)
        
        return Response('', status=200)
    except ValueError as exc:
        return Response(str(exc), status=400)
    except (RuntimeError, requests.RequestException) as exc:
        logger.error('Error handling action: %s', exc, exc_info=True)
        return Response('Internal server error', status=500)


@app.route('/', methods=['GET'])
def health():
    return 'Slack Interactive Server Running\n', 200


if __name__ == '__main__':
    if not SLACK_BOT_TOKEN:
        logger.error('SLACK_BOT_USER_OAUTH_TOKEN required')
        exit(1)
    if not SLACK_SIGNING_SECRET:
        logger.error('SLACK_SIGNING_SECRET required')
        exit(1)
    
    logger.info('Starting server on host %s port %s', DEFAULT_BIND_HOST, PORT)
    app.run(host=DEFAULT_BIND_HOST, port=PORT)
