# Slack Interactive Server

Python server for handling Slack interactive button events. Interactive components allow users to interact with Slack messages through buttons and other UI elements.

## Overview

When users click buttons in Slack messages, Slack sends HTTP POST requests to a configured endpoint. The Python server receives these requests and can perform actions such as sending messages to channels or users.

## Quick Start

Start the server using the Makefile:

```bash
export SLACK_BOT_USER_OAUTH_TOKEN="xoxb-your-token-here"
export PORT=3000
make python-server
```

Or run directly:

```bash
cd python
export SLACK_BOT_USER_OAUTH_TOKEN="xoxb-your-token-here"
export PORT=3000
python3 server.py
```

The server automatically creates a virtual environment and installs dependencies on first run.

## Environment Variables

- `SLACK_BOT_USER_OAUTH_TOKEN` (required): Slack bot OAuth token
- `PORT` (optional): Server port (default: 3000)
- `DEFAULT_ACTION_MESSAGE` (optional): Default message sent when buttons are clicked (default: `"Hello, world!"`)

## Dependencies

The server requires the following Python packages (automatically installed when using `make python-server`):

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
make python-server
```

4. Start ngrok in another terminal:

```bash
make ngrok-up
```

ngrok will display a public HTTPS URL. Use this URL in your Slack app configuration.

### Slack App Configuration

1. Navigate to your Slack app settings at [api.slack.com/apps](https://api.slack.com/apps)
2. Go to <strong>Interactivity & Shortcuts</strong>
3. Enable <strong>Interactivity</strong>
4. Set the <strong>Request URL</strong> to your ngrok URL: `https://your-ngrok-url.ngrok.io/slack/actions`
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
