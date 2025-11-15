#!/usr/bin/env python3
"""
Enhanced Slack Interactive Server with AWS Integration
Demonstrates secure pathways for:
- Triggering K8s API calls via AWS API Gateway + VPC Link
- Downloading and displaying S3 content in Slack messages
"""

import json
import logging
import os
import urllib.parse

import requests
from flask import Flask, request, Response

# Import AWS integration modules
try:
    from aws_integration import get_k8s_client, get_s3_manager
    AWS_INTEGRATION_AVAILABLE = True
except ImportError:
    AWS_INTEGRATION_AVAILABLE = False
    logging.warning('AWS integration modules not available. Install boto3: pip install boto3')

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

PORT = int(os.getenv('PORT', '3000'))
SLACK_BOT_TOKEN = os.getenv('SLACK_BOT_USER_OAUTH_TOKEN', '')
DEFAULT_MESSAGE = os.getenv('DEFAULT_ACTION_MESSAGE', 'Hello, world!')

# Initialize AWS clients if available
k8s_client = None
s3_manager = None

if AWS_INTEGRATION_AVAILABLE:
    try:
        if os.getenv('API_GATEWAY_URL') or os.getenv('K8S_API_URL'):
            k8s_client = get_k8s_client()
            logger.info('K8s API client initialized')
    except Exception as e:
        logger.warning(f'Failed to initialize K8s client: {e}')

    try:
        if os.getenv('S3_BUCKET'):
            s3_manager = get_s3_manager()
            logger.info('S3 manager initialized')
    except Exception as e:
        logger.warning(f'Failed to initialize S3 manager: {e}')


def send_slack_message(channel_id: str, text: str = None, blocks: list = None) -> None:
    """Send message to Slack channel"""
    if not channel_id or not SLACK_BOT_TOKEN:
        raise ValueError('Missing required parameters')
    
    payload = {'channel': channel_id}
    if blocks:
        payload['blocks'] = blocks
    if text:
        payload['text'] = text
    
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
    
    if not data.get('ok'):
        raise RuntimeError(f'Slack API error: {data.get("error")}')


def parse_payload():
    """Parse Slack interactive component payload"""
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
    """Handle Slack interactive component actions"""
    try:
        payload = parse_payload()
        actions = payload.get('actions', [])
        action_id = actions[0].get('action_id') if actions else None
        
        if not action_id:
            return Response('Missing action_id', status=400)
        
        user_id = payload.get('user', {}).get('id')
        channel_id = payload.get('channel', {}).get('id')
        
        # Handle K8s-related actions
        if action_id.startswith('k8s_') and k8s_client:
            try:
                action_value = actions[0].get('value', '{}')
                try:
                    action_data = json.loads(action_value) if isinstance(action_value, str) else action_value
                except json.JSONDecodeError:
                    action_data = {}
                
                k8s_response = k8s_client.call_api(action_id, {
                    'user_id': user_id,
                    'channel_id': channel_id,
                    'action_data': action_data,
                })
                
                # Send result back to Slack
                message = f"✅ Action completed: {k8s_response.get('message', 'Success')}"
                if 'status' in k8s_response:
                    message += f"\nStatus: {k8s_response['status']}"
                
                send_slack_message(channel_id, message)
                
            except Exception as e:
                logger.error(f"K8s API error: {e}", exc_info=True)
                send_slack_message(channel_id, f"❌ Error: {str(e)}")
                return Response('K8s API error', status=500)
        
        # Handle S3-related actions
        elif action_id.startswith('s3_') and s3_manager:
            try:
                action_value = actions[0].get('value', '{}')
                try:
                    action_data = json.loads(action_value) if isinstance(action_value, str) else action_data
                except json.JSONDecodeError:
                    action_data = {}
                
                s3_key = action_data.get('key', '')
                s3_mode = action_data.get('mode', 'link')  # link, upload, image
                
                if not s3_key:
                    send_slack_message(channel_id, "❌ Error: S3 key not provided")
                    return Response('Missing S3 key', status=400)
                
                if action_id == 's3_share_link':
                    # Create link block
                    block = s3_manager.create_link_block(s3_key, action_data.get('title'))
                    send_slack_message(channel_id, blocks=[block])
                    
                elif action_id == 's3_share_image':
                    # Create image block
                    block = s3_manager.create_image_block(s3_key, action_data.get('alt_text'))
                    send_slack_message(channel_id, blocks=[block])
                    
                elif action_id == 's3_upload':
                    # Download and upload to Slack
                    file_metadata = s3_manager.download_and_upload_to_slack(
                        s3_key,
                        SLACK_BOT_TOKEN,
                        channel_id,
                        action_data.get('title')
                    )
                    permalink = file_metadata.get('file', {}).get('permalink', '')
                    send_slack_message(channel_id, f"📎 File uploaded: {permalink}")
                    
                else:
                    send_slack_message(channel_id, f"❌ Unknown S3 action: {action_id}")
                    return Response(f'Unknown S3 action: {action_id}', status=400)
                
            except Exception as e:
                logger.error(f"S3 error: {e}", exc_info=True)
                send_slack_message(channel_id, f"❌ Error: {str(e)}")
                return Response('S3 error', status=500)
        
        # Handle standard actions
        elif action_id == 'send_channel_message':
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


@app.route('/slack/s3/share', methods=['POST'])
def share_s3_content():
    """
    Direct endpoint to share S3 content
    POST body: {"bucket": "...", "key": "...", "channel": "...", "mode": "link|upload|image"}
    """
    if not s3_manager:
        return Response('S3 manager not configured', status=503)
    
    try:
        data = request.get_json()
        bucket = data.get('bucket')
        key = data.get('key')
        channel = data.get('channel')
        mode = data.get('mode', 'link')
        title = data.get('title')
        
        if not all([bucket, key, channel]):
            return Response('Missing required fields: bucket, key, channel', status=400)
        
        # Temporarily override bucket
        original_bucket = s3_manager.bucket
        s3_manager.bucket = bucket
        
        try:
            if mode == 'link':
                block = s3_manager.create_link_block(key, title)
                send_slack_message(channel, blocks=[block])
            elif mode == 'image':
                block = s3_manager.create_image_block(key, title)
                send_slack_message(channel, blocks=[block])
            elif mode == 'upload':
                file_metadata = s3_manager.download_and_upload_to_slack(
                    key, SLACK_BOT_TOKEN, channel, title
                )
                permalink = file_metadata.get('file', {}).get('permalink', '')
                send_slack_message(channel, f"📎 File uploaded: {permalink}")
            else:
                return Response(f'Invalid mode: {mode}', status=400)
        finally:
            s3_manager.bucket = original_bucket
        
        return Response('', status=200)
        
    except Exception as e:
        logger.error(f'Error sharing S3 content: {e}', exc_info=True)
        return Response(str(e), status=500)


@app.route('/', methods=['GET'])
def health():
    """Health check endpoint"""
    status = {
        'status': 'healthy',
        'aws_integration': AWS_INTEGRATION_AVAILABLE,
        'k8s_client': k8s_client is not None,
        's3_manager': s3_manager is not None,
    }
    return Response(
        json.dumps(status, indent=2),
        mimetype='application/json',
        status=200
    )


if __name__ == '__main__':
    if not SLACK_BOT_TOKEN:
        logger.error('SLACK_BOT_USER_OAUTH_TOKEN required')
        exit(1)
    
    logger.info(f'Starting server on port {PORT}')
    logger.info(f'AWS Integration Available: {AWS_INTEGRATION_AVAILABLE}')
    logger.info(f'K8s Client: {"✓" if k8s_client else "✗"}')
    logger.info(f'S3 Manager: {"✓" if s3_manager else "✗"}')
    
    app.run(host='0.0.0.0', port=PORT)
