# Send to Slack

A bash program designed to send [Block Kit](https://docs.slack.dev/reference/block-kit) messages to Slack using either the [Slack Web API](https://api.slack.com/web) with a bot token or a Slack [Incoming Webhook](https://api.slack.com/messaging/webhooks) URL.

## Why bash?

Bash is lightweight, powerful, and easily integrated into existing workflows that can access the shell. Slack offers more robust and widely maintained integrations at their [slackapi](https://github.com/slackapi) org, but these kits are language specific. This project was designed to be included in projects that support multiple languages and want feature parity without relying on more than one toolkit.

Measure twice, send once.

## Prerequisites

- Bash 3.2 or later
- `jq`, `curl`, and `envsubst` (from GNU gettext) for typical payloads

For Web API delivery, a Slack bot token with scopes such as `chat:write` (and often `chat:write.public`). Full scope list: [Getting Started](docs/getting-started.md).

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | bash
```

Default prefix is `${HOME}/.local/bin`. Add it to PATH if needed:

```bash
export PATH="${HOME}/.local/bin:${PATH}"
```

Local checkout, prefixes, containers, and uninstall: [Installation](docs/installation.md).

## Quick start

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

Webhook delivery, keyed block format, and first-run guidance: [Getting Started](docs/getting-started.md).

## Features

- Slack Block Kit with either native `type` blocks or keyed format
- Delivery via bot token (Web API) or Incoming Webhook (`source.webhook_url` or `WEBHOOK_URL`)
- File upload support with automatic image or rich-text block creation (Web API only; webhook delivery skips `file` blocks)
- Crossposting with permalinks and optional custom text (Web API only)
- Thread replies via `params.thread_ts` and `params.thread.replies` (Web API only)
- Update an existing channel message with `chat.update` via `params.message_ts` or `params.message_ts_file` (Web API only)
- Ephemeral channel messages via `chat.postEphemeral` when `params.ephemeral_user` is set (Web API only)
- Retry with exponential backoff on transient delivery failures
- Input flexibility: stdin, `-f|-file|--file`, `params.raw`, or `params.from_file`
- Dry-run mode, dependency health check, and debug mode with sanitized payload logging
- Legacy attachments for colored blocks and tables where Slack allows
- Interactive button components with the optional Python server
- Concourse CI resource type support for pipeline notifications
- Per-message bot display name and avatar via `params.username`, `params.icon_emoji`, and `params.icon_url`

## Documentation

| Guide                                                     | Audience                                       |
| --------------------------------------------------------- | ---------------------------------------------- |
| [Getting Started](docs/getting-started.md)                | First install and first message                |
| [Installation](docs/installation.md)                      | Installer, prefixes, containers, uninstall     |
| [CLI Reference](docs/cli-reference.md)                    | Flags, env vars, health check, debug           |
| [Payload Reference](docs/payload-reference.md)            | Parameters, formats, limits                    |
| [Threading](docs/features/threading.md)                   | Threads and replies                            |
| [Message Management](docs/features/message-management.md) | Updates, crosspost, files                      |
| [Concourse](docs/concourse.md)                            | Resource type and local examples               |
| [Examples catalog](examples/README.md)                    | Executable Concourse pipelines and block demos |
| [Interactive Components](python/README.md)                | Python actions server                          |
| [CI Scripts](ci/README.md)                                | Maintainer automation, tests, and image builds |

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.

## References

- [Slack Block Kit](https://api.slack.com/block-kit) - Official documentation for Slack message formatting
- [Slack Web API](https://api.slack.com/web) - Reference for Slack API endpoints and methods
- [Concourse Resource Types](https://concourse-ci.org/resource-types.html) - Concourse CI resource type documentation
