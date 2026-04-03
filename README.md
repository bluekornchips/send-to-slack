# Send to Slack

A bash program designed to send [Block Kit](https://docs.slack.dev/reference/block-kit) messages to Slack using either the [Slack Web API](https://api.slack.com/web) with a bot token or a Slack [Incoming Webhook](https://api.slack.com/messaging/webhooks) URL.

## Why bash?

Bash is lightweight, powerful, and easily integrated into existing workflows that can access the shell. Slack offers more robust and widely maintained integrations at their [slackapi](https://github.com/slackapi) org, but these kits are language specific. This project was designed to be included in projects that support multiple languages and want feature parity without relying on more than one toolkit.

Measure twice, send once.

## Running Locally

Clone the repository and run the script directly:

```bash
git clone https://github.com/bluekornchips/send-to-slack.git
cd send-to-slack
./bin/send-to-slack.sh -h
```

To make the command available in your current shell session without moving files:

```bash
alias send-to-slack="$(pwd)/bin/send-to-slack.sh"
```

Persist the alias by adding it to your shell rc file:

```bash
echo 'alias send-to-slack="path/to/send-to-slack/bin/send-to-slack.sh"' >> ~/.bashrc
```

## Remote Install (curl | bash)

Install with a single command. The script is fetched from the repository default branch on GitHub, then the installer clones that repository with `git` or, if `git` is missing, downloads a source tarball with `curl` and extracts it with `tar`.

```bash
curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | bash
```

The installer:

- Needs `git`, or both `curl` and `tar`, to obtain the project tree after the install script itself is downloaded
- Installs `lib/`, helper scripts under `bin/`, and the main CLI under a fixed install root, then symlinks `send-to-slack` into your chosen prefix
- Installs to `${HOME}/.local/bin` by default; when run as root installs to `/usr/local/bin` (override with `--prefix` or `--prefix=<dir>`)
- Refuses system paths under `/usr` or `/etc` except `/usr/local` (no sudo required)

Set `GITHUB_REPO` to `owner/repo` to install from a fork.

Options:

- `--version <ref>` - Branch or tag to install (default: `main`). Use `local` when running `bin/install.sh` from a checkout to install that tree; `local` is not supported when the script is piped from `curl`, so the installer falls back to a remote ref.
- `--prefix <dir>` or `--prefix=<dir>` - Target directory (default: `${HOME}/.local/bin`, or `/usr/local/bin` when run as root)
- `--force` - Overwrite an existing `send-to-slack` in the prefix when it lacks the install signature

Example with custom prefix (useful in containers):

```bash
curl --proto "=https" --tlsv1.2 --fail --show-error --location \
  https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | \
  bash -s -- --prefix /tmp/send-to-slack/bin
```

Same with equals form:

```bash
curl --proto "=https" --tlsv1.2 --fail --show-error --location \
  https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | \
  bash -s -- --prefix=/tmp/send-to-slack/bin
```

After installation, add the prefix to your PATH if needed (when run as root the default `/usr/local/bin` is already on PATH):

```bash
export PATH="${HOME}/.local/bin:${PATH}"
```

## Install

Run from the cloned repository:

```bash
./bin/install.sh
```

Install from the working tree without hitting GitHub:

```bash
./bin/install.sh --version local
```

- Default prefix is `${HOME}/.local/bin` (or `/usr/local/bin` when run as root); override with `--prefix <dir>` or `--prefix=<dir>` when the default is not writable, for example `--prefix /tmp/send-to-slack/bin` inside containers.
- If the prefix is not on PATH, add it: `export PATH="${HOME}/.local/bin:${PATH}"` (or the prefix you chose; root installs to `/usr/local/bin` which is on PATH).
- The installer copies `bin/send-to-slack.sh`, `lib/`, and `bin` helpers into an install root, symlinks `send-to-slack` into the prefix, marks the main script executable, and appends a small signature comment used by `uninstall.sh`.

## Uninstall

Run from the cloned repository:

```bash
./bin/uninstall.sh
```

- Uninstall removes the installed send-to-slack shim only when it carries the install signature; use --force to override.
- It is safe to run when the file is already absent (no-op).

## Container Images

The container images are available on Docker Hub as `sunflowersoftware/send-to-slack`.

```bash
docker pull sunflowersoftware/send-to-slack
```

### Building Images

Two Dockerfiles are provided in the `Docker/` directory:

- `Docker/Dockerfile`: CI image that copies the repository into `/usr/local/send-to-slack` and exposes `send-to-slack` on `PATH`
- `Docker/Dockerfile.concourse`: Concourse resource-type image with only the runtime dependencies needed by the `check`, `in`, and `out` scripts

Build examples (run from repo root):

```bash
docker build -f Docker/Dockerfile -t send-to-slack-ci:local .
docker build -f Docker/Dockerfile.concourse -t send-to-slack-concourse .
```

### CI Build Helper

`ci/build.sh` builds the Docker image and can optionally run a healthcheck and send a test message using the local script:

```bash
# Build only
ci/build.sh

# Build + healthcheck + test message, requires CHANNEL and SLACK_BOT_USER_OAUTH_TOKEN
CHANNEL=test SLACK_BOT_USER_OAUTH_TOKEN=token ci/build.sh --healthcheck --send-test-message
```

### Development Usage

For development or testing, you can run the script directly:

```bash
./bin/send-to-slack.sh
```

When running directly from the repository, the script will automatically detect its location and find source files.

## Quick Start

Send a Slack message by piping JSON to the tool:

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

The tool also accepts the keyed format:

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
        "section": {
          "type": "text",
          "text": {
            "type": "plain_text",
            "text": "Hello, world!"
          }
        }
      }
    ]
  }
}
EOF
```

Blocks can also be provided from a file:

```bash
send-to-slack --file payload.json
```

When running directly from the repository, use `./bin/send-to-slack.sh` instead of `send-to-slack`.

## CLI Usage

- Reads JSON from stdin when no file is provided.
- Use `-f`, `-file`, or `--file` to point at a payload file.
- Use `-v` or `--version` to display version information and exit.
- Use `-h` or `--help` to display usage information and exit.
- Use `--health-check` to validate required dependencies without sending a message.
- Emits Concourse-style JSON (`version`, `metadata`) to stdout unless `SEND_TO_SLACK_OUTPUT` is set.

## Health Check

Use `--health-check` to validate dependencies `jq` and `curl` and optionally test Slack Web API connectivity if `SLACK_BOT_USER_OAUTH_TOKEN` is set. There is no separate probe for Incoming Webhook URLs. Returns exit code 0 on success, 1 on failure. Skips the API check if `DRY_RUN` or `SKIP_SLACK_API_CHECK` is set.

## Environment Variables

The following environment variables control tool behavior:

- `SLACK_BOT_USER_OAUTH_TOKEN` - Slack bot OAuth token when missing from `source`. After payload merge, a non-empty token selects Web API delivery.
- `WEBHOOK_URL` - Incoming Webhook URL when `source.webhook_url` is empty. Used only when no bot token is in effect, matching `source.webhook_url` semantics.
- `CHANNEL` - Target Slack channel when `params.channel` is empty. Required for Web API delivery. For webhooks, optional when the hook URL already targets a channel.
- `DRY_RUN` - Set to `true` to validate without sending messages
- `SEND_TO_SLACK_OUTPUT` - File path to write JSON output instead of stdout
- `SEND_TO_SLACK_PAYLOAD_BASE_DIR` - First directory tried when resolving relative paths for `params.from_file` and block-level `from_file` (the Concourse resource `out` script sets this to the step destination directory)
- `SHOW_METADATA` - Set to `false` to disable metadata output (default: `true`)
- `SHOW_PAYLOAD` - Set to `false` to exclude payload from metadata (default: `true`)
- `SKIP_SLACK_API_CHECK` - Set to `true` to skip API connectivity check in health check mode
- `LOG_VERBOSE` - Set to `true` to log verbose request details (channel, ts, block count, sanitized payload) for each Slack API send

## Debug Mode

Enable debug mode by setting `params.debug: true` in your payload. When enabled, debug mode provides enhanced visibility for troubleshooting:

### Features

- Sanitized Payload Logging: Logs the input payload to stderr with sensitive authentication tokens redacted as `[REDACTED]`. This allows you to inspect the payload structure without exposing credentials.
- Automatic Metadata Override: Forces `SHOW_METADATA` and `SHOW_PAYLOAD` to `true`, ensuring full metadata output regardless of environment variable settings.
- Extended Debug Output: When enabled, also logs input source, block processing flow (type and destination per block), payload loading source (raw or from_file), configuration (channel, dry_run), send/crosspost request summaries, file upload steps, and mention resolution (user/channel/DM lookups).

### Usage

```json
{
  "source": {
    "slack_bot_user_oauth_token": "xoxb-your-token"
  },
  "params": {
    "channel": "notifications",
    "debug": true,
    "blocks": []
  }
}
```

When debug mode is enabled, you'll see output like:

```
parse_payload:: input payload (sanitized):
{
  "source": {
    "slack_bot_user_oauth_token": "[REDACTED]"
  },
  "params": {
    "channel": "notifications",
    "blocks": []
  }
}
```

Debug mode redacts authentication tokens but still logs the payload structure.

## Features

- Slack Block Kit with either native `type` blocks or keyed format
- Delivery via bot token, Web API, or Incoming Webhook (`source.webhook_url` or `WEBHOOK_URL`)
- File upload support with automatic image or rich-text block creation (Web API only; webhook delivery skips `file` blocks with a clear message)
- Crossposting with permalinks and optional custom text (Web API only; webhook delivery skips crosspost)
- Thread replies and thread creation for multi-block messages, plus `thread_replies` array for multiple replies in a thread (Web API only; webhook delivery skips thread replies)
- Update an existing channel message with `chat.update` when `params.message_ts` is set (Web API only; requires `params.channel` in the same JSON payload; skips new post, thread replies, and crosspost for that run)
- Ephemeral channel messages via `chat.postEphemeral` when `params.ephemeral_user` is set (Web API only; incompatible with webhooks; skips thread replies, crosspost, and permalink)
- Retry with exponential backoff on delivery for transient failures
- Input flexibility: stdin, `-f|-file|--file`, `params.raw`, or `params.from_file`
- Dry-run mode, dependency health check, and rich validation output
- Debug mode with sanitized payload logging for troubleshooting
- Legacy attachments for colored blocks and tables where Slack allows
- Interactive button components with the optional Python server
- Concourse CI resource type support for pipeline notifications

## Requirements

### Runtime Dependencies

- Bash 3.2 or later (project shell style targets Bash 3.2 plus)
- `jq` - [jqlang](https://github.com/jqlang/jq) for JSON processing
- `curl` - [curl](https://curl.se/) for HTTP requests
- `envsubst` from [GNU gettext](https://www.gnu.org/software/gettext/) (usually in the `gettext` package) for variable interpolation in blocks

### Interactive Components Dependencies

- Python 3.9 or later (for interactive button handling)
- Flask 3.0.0 or later (for web server)
- requests 2.31.0 or later (for HTTP requests to Slack API)
- Docker (optional, for running ngrok in a container as documented under `python/`)

### Slack Configuration

Slack bot token with appropriate OAuth scopes. Posting, updating, ephemeral sends, and thread replies need `chat:write`; some channels also need `chat:write.public`.

- `chat:write` - Post, update, and thread messages via Web API
- `channels:read`, `groups:read`, `im:read` - Channel, private channel, and DM access for lookups where used
- `files:write`, `files:read` - File operations
- `users:read` - User information for mention resolution and similar features

See [Slack API Scopes](https://api.slack.com/scopes) for complete documentation.

## Usage

`send-to-slack` expects a JSON payload. Provide it on stdin or with `-f|-file|--file`. You can also embed the payload through `params.raw` (stringified JSON) or `params.from_file` (path to a JSON file). When the `source` object is missing or omits credentials, the tool falls back to environment variables: `SLACK_BOT_USER_OAUTH_TOKEN` or `WEBHOOK_URL` for auth, plus `CHANNEL` and `DRY_RUN` where applicable.

Configure one delivery method: `source.slack_bot_user_oauth_token` for the Web API or `source.webhook_url` for an Incoming Webhook. If both are present in `source`, the bot token wins and the Web API is used.

### Payload Structure

Web API example:

```json
{
  "source": {
    "slack_bot_user_oauth_token": "xoxb-your-token"
  },
  "params": {
    "channel": "channel-name-or-id",
    "blocks": [],
    "text": "optional fallback text",
    "dry_run": false,
    "debug": false,
    "thread_ts": "1763161862.880069",
    "create_thread": false,
    "thread_replies": [],
    "crosspost": {
      "channel": ["#channel1", "#channel2"],
      "blocks": [
        {
          "type": "section",
          "text": { "type": "plain_text", "text": "Crosspost body" }
        }
      ],
      "no_link": false
    },
    "raw": "{\"source\":{},\"params\":{\"channel\":\"channel-name-or-id\",\"blocks\":[]}}",
    "from_file": "./payload.json",
    "ephemeral_user": "U012AB3CD"
  }
}
```

Set `params.message_ts` to the Slack message `ts` of an existing message to call [`chat.update`](https://api.slack.com/methods/chat.update) instead of posting a new message. Requires Web API delivery, `params.channel` set in the same JSON payload as the timestamp (the tool reads the raw input file for this path, so `CHANNEL` alone is not enough), and the usual `params.blocks` and optional `params.text`. Thread replies, crosspost, and ephemeral flows are not run on an update invocation. Use the `chat:write` scope. After a successful post or update, Concourse-style output includes `version.message_ts` when the API returns a `ts`. See [examples/update-message.yaml](examples/update-message.yaml).

Set `params.ephemeral_user` to a Slack user ID to send with [`chat.postEphemeral`](https://api.slack.com/methods/chat.postEphemeral) instead of `chat.postMessage`. Only that user sees the message in the channel. Requires Web API delivery with a bot token; it cannot be used with `source.webhook_url` as the only delivery method. Thread replies, crosspost, and permalink metadata are not supported for ephemeral sends. Use the `chat:write` scope. See [examples/ephemeral.yaml](examples/ephemeral.yaml).

Incoming Webhook example. You may omit `params.channel` when the webhook URL is already bound to a channel in Slack:

```json
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
```

### Required Parameters

Web API:

- `source.slack_bot_user_oauth_token` or `SLACK_BOT_USER_OAUTH_TOKEN`
- `params.channel` or `CHANNEL` (for `params.message_ts` updates, set `params.channel` in the JSON; see Updating messages)
- `params.blocks` for typical new messages; updates may use `params.text` with an empty `blocks` array when Slack accepts that shape

Incoming Webhook:

- `source.webhook_url` or `WEBHOOK_URL`, with no bot token in effect
- `params.blocks`
- `params.channel` or `CHANNEL` only when you need to override or supply a channel for tooling that expects it; many webhook-only payloads omit `channel` like [examples/webhook-slack.yaml](examples/webhook-slack.yaml)

### Optional source fields

- `source.webhook_url` - Slack Incoming Webhook URL for delivery when no bot token applies; not used together with Web API delivery from `source.slack_bot_user_oauth_token`

### Optional Parameters

- `params.debug` - Set to `true` to enable debug mode (default: `false`). When enabled:
  - Logs sanitized input payload (with auth tokens redacted) to stderr for debugging
  - Overrides `SHOW_METADATA` and `SHOW_PAYLOAD` to `true` regardless of environment variable settings
  - Logs input source, block processing flow, payload loading, configuration, send/crosspost summaries, file upload steps, and mention resolution
- `params.text` - Fallback text for notifications (max 40,000 characters)
- `params.dry_run` - Set to `true` to validate without sending (default: `false`)
- `params.thread_ts` - Thread timestamp or Slack message permalink (see Threading)
- `params.create_thread` - Set to `true` to create a new thread (see Threading)
- `params.thread_replies` - Array of message configs; each entry is sent as a separate reply in the thread (see Threading)
- `params.crosspost` - Crosspost configuration (see Crossposting)
- `params.raw` - JSON string that replaces the `params` object
- `params.from_file` - Path to JSON that replaces the `params` object
- `params.blocks` - Array of block configurations
- `params.message_ts` - Slack message timestamp for `chat.update`; Web API only; requires `params.channel` in the payload; omits new post, thread replies, and crosspost for that run (see Updating messages above)
- `params.ephemeral_user` - Slack user ID for `chat.postEphemeral`; Web API only, not valid with webhook-only delivery (see Ephemeral messages in the Web API example above)

### Block Formats

Blocks can be provided in either format:

- Native Slack format:

```json
{ "type": "section", "text": { "type": "plain_text", "text": "Hello" } }
```

- Keyed format:

```json
{
  "section": {
    "type": "text",
    "text": { "type": "plain_text", "text": "Hello" }
  }
}
```

- Block-level `from_file`: Load one or more blocks from a JSON file. The file may contain a single block object or an array of blocks. Path resolution matches `params.from_file` (relative paths use `SEND_TO_SLACK_PAYLOAD_BASE_DIR` then `PWD`):

```json
{ "from_file": "blocks.json" }
```

Named colors on a block (`danger`, `success`, `warning`) or a `table` block are wrapped in legacy attachments automatically.

### Message Limits

- Maximum 50 blocks per message (including blocks inside attachments)
- Maximum 20 attachments per message
- Maximum 40,000 characters for `text` fields

## Threading

Threading features apply to Web API delivery only. Incoming Webhook delivery skips `thread_replies`, `create_thread`, and threaded sends that depend on `thread_ts`.

`create_thread` and `thread_ts` are mutually exclusive. `thread_ts` can be supplied as either a Slack timestamp or a permalink; the tool converts permalinks automatically. When `create_thread` is `true` and multiple blocks are present, the first block is sent as the parent message and the remaining blocks are sent as the thread reply.

### Replying to Existing Threads

Provide `thread_ts` with the parent message timestamp. Extract from the permalink (the shareable url): `p1763161862880069` becomes `1763161862.880069` with the decimal inserted after 10 digits.

```json
{
  "params": {
    "channel": "notifications",
    "thread_ts": "1763161862.880069",
    "blocks": [
      {
        "type": "section",
        "text": { "type": "plain_text", "text": "Reply in thread" }
      }
    ]
  }
}
```

### Creating New Threads

Set `create_thread: true` with multiple blocks. First block sent as regular message, remaining blocks sent as thread reply.

```json
{
  "params": {
    "channel": "notifications",
    "create_thread": true,
    "blocks": [
      {
        "type": "section",
        "text": { "type": "plain_text", "text": "Parent message" }
      }
    ]
  }
}
```

### Multiple Replies in a Thread

Use `thread_replies` to send several messages as separate replies in the same thread. Each element is a message config (e.g. `blocks`, optional `text`). The thread is determined by `thread_ts` or, when using `create_thread: true`, by the initial message. See [examples/thread-replies.yaml](examples/thread-replies.yaml) for a full example.

```json
{
  "params": {
    "channel": "notifications",
    "create_thread": true,
    "blocks": [
      {
        "section": {
          "type": "text",
          "text": { "type": "mrkdwn", "text": "Parent" }
        }
      }
    ],
    "thread_replies": [
      {
        "blocks": [
          {
            "section": {
              "type": "text",
              "text": { "type": "mrkdwn", "text": "Reply 1" }
            }
          }
        ]
      },
      {
        "blocks": [
          {
            "section": {
              "type": "text",
              "text": { "type": "mrkdwn", "text": "Reply 2" }
            }
          }
        ]
      }
    ]
  }
}
```

## Updating messages

When `params.message_ts` is present, the tool calls Slack `chat.update` with the parsed payload, `params.channel`, and that timestamp. Incoming Webhooks are not supported. For that run the tool does not call `chat.postMessage`, `send_thread_replies`, or `crosspost_notification`. Supply `params.channel` in the JSON; the update branch reads the raw input file and does not substitute the `CHANNEL` environment variable for this check. Concourse output `version` includes `message_ts` when the API response contains `ts`. See [examples/update-message.yaml](examples/update-message.yaml).

## Crossposting

Crossposting uses the Web API and permalinks. Incoming Webhook delivery skips crosspost; the tool logs that on stderr.

The program supports crossposting messages to additional channels after the initial notification is sent. Crosspost accepts the same params as a regular message, including blocks, text, thread_ts, and all other message params.

### Crosspost Configuration

Add a `crosspost` object to your `params` section:

```json
{
  "params": {
    "channel": "#main-channel",
    "blocks": [
      {
        "type": "section",
        "text": { "type": "plain_text", "text": "Main announcement" }
      }
    ],
    "crosspost": {
      "channel": ["#channel1", "#channel2"],
      "blocks": [
        {
          "section": {
            "type": "text",
            "text": {
              "type": "mrkdwn",
              "text": "Check out the original announcement!"
            }
          }
        }
      ]
    }
  }
}
```

### Crosspost Parameters

- `crosspost.channel` - Channel name or ID; accepts a string or array
- `crosspost.channels` - Alias for `crosspost.channel`; also accepts a string or array
- `crosspost.blocks` - Block Kit blocks to send, same format as `params.blocks`
- `crosspost.text` - Optional fallback text for notifications
- `crosspost.no_link` - Set to `true` to disable automatic permalink appending

All other params supported by regular messages are also supported in crosspost.

### Permalink in Crosspost

The `$NOTIFICATION_PERMALINK` environment variable is available for use in crosspost blocks via envsubst. By default, a context block with a link to the original message is automatically appended unless `no_link: true` is set.

### How It Works

1. The initial notification is sent to the channel specified in `params.channel`
2. After successful delivery, the permalink to the original message is stored in `$NOTIFICATION_PERMALINK`
3. For each channel in `crosspost.channel` or `crosspost.channels`, a new message is created using the crosspost params
4. Unless `no_link: true`, a context block with a link to the original message is appended
5. If a crosspost fails for a specific channel, the error is logged but processing continues for remaining channels

## File Uploads

Use the `file` block type to upload files through Slack's `files.getUploadURLExternal` flow. File blocks are not supported for Incoming Webhook delivery.

- Required: `path` to the file and a resolvable `channel` (from `params.channel` or `CHANNEL`) for Web API delivery
- Optional: `title` (defaults to filename) and `interpolate_file_contents_to_var` to export file contents to an environment variable
- Files up to 1 GB are supported
- Image files (png, jpg, jpeg, gif) create image blocks; other files create rich-text blocks that link to the uploaded file

## Supported Block Types

The program supports all Slack Block Kit block types. See [examples/README.md](examples/README.md) for detailed documentation and examples:

- Section, Header, Divider, Context blocks
- Markdown and Rich Text blocks
- Actions blocks (interactive buttons)
- Image blocks (standalone image display)
- Video blocks (video embedding)
- Table blocks (legacy attachments)
- File upload blocks

## Additional Documentation

- [Examples](examples/README.md) - Complete block type documentation and examples
- [Concourse CI Integration](concourse/README.md) - Using as a Concourse resource type
- [Interactive Components](python/README.md) - Python server setup for interactive buttons

## Development Tools

### Block Kit Builder

Before creating your payload, go take a look at Slack's [Block Kit Builder](https://app.slack.com/block-kit-builder) to visually design and see how your message layout will look. It's better than trying to figure out payloads by brute forcing tests.

The Builder allows you to:

- Drag and drop blocks to create your layout
- See a live preview of how your message will appear
- Export the JSON structure for use in your code

#### Example Workflow:

1. Design in Block Kit Builder: Open the [Block Kit Builder](https://app.slack.com/block-kit-builder) and design your message layout visually
2. Export JSON: Copy the generated JSON from the Builder
3. Choose a format: You can paste the native `type` objects directly or wrap them in the keyed format (e.g., `{"section": {...}}`) inside `params.blocks`
4. Use in Tool: Include the blocks in your payload and run `send-to-slack`

The Block Kit Builder exports blocks in Slack's native format, which the tool accepts directly.

## Development

### Running Tests

```bash
make test            # Run all tests
make test-all        # Run all tests (with smoke and acceptance flags)
make test-smoke      # Run smoke tests only
make test-acceptance # Run acceptance tests only
```

Some smoke and acceptance tests for Incoming Webhooks run only when `SLACK_WEBHOOK_URL` is set in the environment. Without it, those tests are skipped. With it, the suite also checks that webhook delivery rejects `params.ephemeral_user` and `params.message_ts`, since those require the Web API.

### Local Concourse Development

```bash
make concourse-up                  # Start local Concourse server
make concourse-down                # Stop local Concourse server
make concourse-load-examples       # Load example pipelines
make concourse-run-all-examples    # Run all example pipelines end-to-end (CI)
```

Environment variables for `make concourse-load-examples`, each passed to `fly set-pipeline -v`:

- `SLACK_BOT_USER_OAUTH_TOKEN` - Slack bot OAuth token for pipelines that use the Web API
- `CHANNEL` - Primary Slack channel for examples that need `channel`
- `SIDE_CHANNEL` - Secondary channel for examples that use `side_channel`, may be empty
- `SLACK_WEBHOOK_URL` - Incoming Webhook URL for [examples/webhook-slack.yaml](examples/webhook-slack.yaml), may be empty if you skip that pipeline

### Development Dependencies

- `bats` - [Bash Automated Testing System](https://github.com/bats-core/bats-core)
- `shellcheck` - [Shell script static analysis](https://github.com/koalaman/shellcheck); required for `make lint`
- `shfmt` - [Shell script formatter](https://github.com/mvdan/sh); optional locally, included in `Docker/Dockerfile.test` if you use that image

## Contributing

Contributions are not welcome at this time.

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.

## References

- [Slack Block Kit](https://api.slack.com/block-kit) - Official documentation for Slack message formatting
- [Slack Web API](https://api.slack.com/web) - Reference for Slack API endpoints and methods
- [Concourse Resource Types](https://concourse-ci.org/resource-types.html) - Concourse CI resource type documentation
