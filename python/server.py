#!/usr/bin/env python3

import json
import logging
import os
import urllib.parse

import requests
from flask import Flask, request, Response

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

PORT = int(os.getenv('PORT', '3000'))
SLACK_BOT_TOKEN = os.getenv('SLACK_BOT_USER_OAUTH_TOKEN', '')
DEFAULT_MESSAGE = os.getenv('DEFAULT_ACTION_MESSAGE', 'Hello, world!')


def send_slack_message(channel_id: str, text: str) -> None:
    if not channel_id or not text or not SLACK_BOT_TOKEN:
        raise ValueError('Missing required parameters')
    
    response = requests.post(
        'https://slack.com/api/chat.postMessage',
        headers={
            'Authorization': f'Bearer {SLACK_BOT_TOKEN}',
            'Content-Type': 'application/json',
        },
        json={'channel': channel_id, 'text': text},
        timeout=30,
    )
    
    response.raise_for_status()
    data = response.json()
    
    if not data.get('ok'):
        raise RuntimeError(f'Slack API error: {data.get("error")}')


def parse_payload():
    body = request.get_data(as_text=True)
    if not body:
        raise ValueError('Payload is required')
    
    if 'payload=' in body:
        params = urllib.parse.parse_qs(body)
        encoded = params.get('payload', [None])[0]
        if encoded:
            return json.loads(urllib.parse.unquote_plus(encoded))
    
    return json.loads(body) if isinstance(body, str) else body


@app.route('/slack/actions', methods=['POST'])
def handle_actions():
    try:
        payload = parse_payload()
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
    except ValueError as e:
        return Response(str(e), status=400)
    except Exception as e:
        logger.error(f'Error: {e}', exc_info=True)
        return Response('Internal server error', status=500)


@app.route('/', methods=['GET'])
def health():
    return 'Slack Interactive Server Running\n', 200


if __name__ == '__main__':
    if not SLACK_BOT_TOKEN:
        logger.error('SLACK_BOT_USER_OAUTH_TOKEN required')
        exit(1)
    
    logger.info(f'Starting server on port {PORT}')
    app.run(host='0.0.0.0', port=PORT)
