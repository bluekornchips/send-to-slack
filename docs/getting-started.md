# Getting Started

Install `send-to-slack`, then send a first message with a bot token or an Incoming Webhook.

## Prerequisites

- Bash 3.2+, `jq`, `curl`
- `envsubst` (GNU gettext) if your blocks use variable interpolation
- Web API: a Slack bot token with at least `chat:write` (often also `chat:write.public`)

Other scopes used by optional features:

| Scope                                     | Used for                                    |
| ----------------------------------------- | ------------------------------------------- |
| `chat:write.customize`                    | `params.username`, `icon_emoji`, `icon_url` |
| `files:write`, `files:read`               | File uploads                                |
| `users:read`                              | Mention resolution                          |
| `channels:read`, `groups:read`, `im:read` | Channel and DM lookups                      |

Full Slack scope reference: [api.slack.com/scopes](https://api.slack.com/scopes).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | bash
export PATH="${HOME}/.local/bin:${PATH}"
```

More install options: [Installation](installation.md). From a checkout, run `./bin/send-to-slack.sh` instead of `send-to-slack`.

## Send with a bot token

```bash
cat <<'EOF' | send-to-slack
{
  "source": {
    "slack_bot_user_oauth_token": "xoxb-your-token"
  },
  "params": {
    "channel": "notifications",
    "blocks": [
      {
        "type": "section",
        "text": {
          "type": "plain_text",
          "text": "Hello, world!"
        }
      }
    ]
  }
}
EOF
```

Keyed blocks, `--file`, and full params: [Payload Reference](payload-reference.md). Preview layouts in Slack's [Block Kit Builder](https://app.slack.com/block-kit-builder).

## Send with a webhook

```bash
cat <<'EOF' | send-to-slack
{
  "source": {
    "webhook_url": "https://hooks.slack.com/services/<workspace-id>/<app-id>/<token>"
  },
  "params": {
    "blocks": [
      {
        "type": "section",
        "text": {
          "type": "plain_text",
          "text": "Hello via webhook"
        }
      }
    ]
  }
}
EOF
```

`params.channel` is optional when the webhook URL is already bound to a channel. If both a bot token and a webhook URL are set in `source`, the bot token wins.

Webhooks do not support file uploads, crosspost, thread replies, updates, or ephemeral messages. Use the Web API for those: [Message Management](features/message-management.md).

## Next steps

- [CLI Reference](cli-reference.md)
- [Payload Reference](payload-reference.md)
- [Examples catalog](../examples/README.md)
