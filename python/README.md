# Slack Interactive Server

Python server for handling Slack interactive button events. Interactive components allow users to interact with Slack messages through buttons and other UI elements.

## Overview

When users click buttons in Slack messages, Slack sends HTTP POST requests to a configured endpoint. The Python server receives these requests and can perform actions such as sending messages to channels or users.

## Quick Start

From the repository root, the Python targets live in `python/Makefile`. Use `-C python`:

```bash
export SLACK_BOT_USER_OAUTH_TOKEN="xoxb-your-token-here"
export SLACK_SIGNING_SECRET="your-signing-secret"
export PORT=3000
make -C python python-server
```

Or run directly:

```bash
cd python
export SLACK_BOT_USER_OAUTH_TOKEN="xoxb-your-token-here"
export SLACK_SIGNING_SECRET="your-signing-secret"
export PORT=3000
python3 -m venv .venv && .venv/bin/pip install flask requests && .venv/bin/python server.py
```

The `make -C python python-server` target creates `.venv` under `python/` and installs dependencies on first run.

## Environment Variables

- `SLACK_BOT_USER_OAUTH_TOKEN` (required): Slack bot OAuth token
- `SLACK_SIGNING_SECRET` (required): Signing secret for request verification
- `PORT` (optional): Server port (default: 3000)
- `BIND_HOST` (optional): Host to bind (default: 127.0.0.1)
- `DEFAULT_ACTION_MESSAGE` (optional): Default message sent when buttons are clicked (default: `"Hello, world!"`)
- `LOG_LEVEL` (optional): Logging level (default: INFO). Set to `DEBUG` to log incoming payload summaries, action context, and Slack API request/response details.

## Dependencies

The server requires the following Python packages (installed by `make -C python python-server`):

- `flask>=3.0.0` - Web framework for handling HTTP requests
- `requests>=2.31.0` - HTTP library for Slack API calls

## Server Endpoints

- `POST /slack/actions` - Receives interactive component payloads from Slack
- `GET /` - Health check endpoint

## Supported Action IDs

The server handles the following action IDs:

- `send_channel_message` - Sends a message to the channel where the button was clicked
- `send_user_message` - Sends a direct message to the user who clicked the button
- `test_action` - Sends a test message to the channel

## ngrok Integration

For local development, use ngrok to expose the Python server to the internet. Slack requires a publicly accessible HTTPS endpoint for interactive components.

### Prerequisites

- Docker installed and running
- ngrok account and authtoken

### Setup

1. Get your ngrok authtoken from the [ngrok dashboard](https://dashboard.ngrok.com/get-started/your-authtoken)

2. Configure environment variables:

```bash
export NGROK_AUTHTOKEN="your-ngrok-authtoken"
export NGROK_URL="your-custom-domain.ngrok.io"  # Optional, for custom domains
```

3. Start the Python server in one terminal:

```bash
make -C python python-server
```

4. Start ngrok in another terminal:

```bash
export NGROK_AUTHTOKEN="your-token"
# Optional reserved hostname, otherwise ngrok assigns a URL each run:
# export NGROK_URL="https://your-name.ngrok-free.app"
make -C python ngrok-up
```

ngrok will display a public HTTPS URL. Use this URL in your Slack app configuration.

### Slack App Configuration

1. Navigate to your Slack app settings at [api.slack.com/apps](https://api.slack.com/apps)
2. Open Interactivity and Shortcuts
3. Enable Interactivity
4. Set the Request URL to your ngrok URL, for example `https://your-ngrok-host/slack/actions`
5. Save changes

## Testing Interactive Components

1. Send a message with action blocks using the bash script:

```bash
echo '{
  "source": {
    "slack_bot_user_oauth_token": "xoxb-your-token"
  },
  "params": {
    "channel": "notifications",
    "blocks": [
      {
        "section": {
          "type": "text",
          "text": {
            "type": "mrkdwn",
            "text": "Click the button below to test interactivity."
          }
        }
      },
      {
        "actions": {
          "elements": [
            {
              "type": "button",
              "text": {
                "type": "plain_text",
                "text": "Send to Channel"
              },
              "action_id": "send_channel_message",
              "style": "primary"
            }
          ]
        }
      }
    ]
  }
}' | send-to-slack
```

2. Click the button in Slack
3. Verify the server receives the request and sends a response message

## Additional Configuration

For interactive components, you'll need:

- Interactive Components URL configured in Slack app settings
- ngrok tunnel URL (for local development) or public HTTPS endpoint (for production)

See the main [README.md](../README.md) for Slack bot token OAuth scopes required for interactive components.
