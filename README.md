# Send to Slack

A bash program designed to send [block kit content](https://docs.slack.dev/reference/block-kit) to Slack via the Slack Web API.

## Why bash?

Bash is lightweight, powerful, and easily integrated into existing workflows that can access the shell. Slack offers more robust and widely maintained integrations at their [slackapi](https://github.com/slackapi) org, but these kits are language specific. This project was designed to be included in projects that support multiple languages and want feature parity without relying on more than one toolkit.

Measure twice, send once.

## Installation

### Quick Install

Install to `~/.local` (default, no sudo required):

```bash
curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | bash
```

Installs to `~/.local/bin/send-to-slack` and supporting files to `~/.local/lib/send-to-slack/`.

**System installation (requires sudo):**

```bash
curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/bin/install.sh | sudo bash
```

Installs to `/usr/local/bin/send-to-slack` and supporting files to `/usr/local/lib/send-to-slack/`.

### From Source

For development or testing without installation, you can use the script directly from the repository:

```bash
git clone https://github.com/bluekornchips/send-to-slack.git
cd send-to-slack
alias send-to-slack="$(pwd)/bin/send-to-slack.sh"
```

Or add the alias to your shell rc file:

```bash
echo 'alias send-to-slack="path/to/send-to-slack/bin/send-to-slack.sh"' >> ~/.bashrc
```

### Uninstallation

Use the uninstall script to remove all installed files. For user-local installations:

```bash
./bin/uninstall.sh ~/.local
```

For system installations:

```bash
sudo ./bin/uninstall.sh /usr/local
```

Or use `--force` flag for protected prefixes:

```bash
sudo ./bin/uninstall.sh --force /usr/local
```

The uninstall script uses the installation manifest at `$prefix/lib/send-to-slack/install_manifest.txt` to remove all files that were installed.

## Container Image

The container image is available on Docker Hub as `sunflowersoftware/send-to-slack`.

```bash
docker pull sunflowersoftware/send-to-slack
```

### Development Usage

For development or testing without installation, you can use the script directly:

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

Use `--health-check` to validate dependencies (`jq`, `curl`) and optionally test Slack API connectivity if `SLACK_BOT_USER_OAUTH_TOKEN` is set. Returns exit code 0 on success, 1 on failure. Skips API check if `DRY_RUN` or `SKIP_SLACK_API_CHECK` is set.

## Environment Variables

The following environment variables control tool behavior:

- `SLACK_BOT_USER_OAUTH_TOKEN` - Slack bot OAuth token (fallback if not in `source`)
- `CHANNEL` - Target Slack channel (fallback if not in `params.channel`)
- `DRY_RUN` - Set to `true` to validate without sending messages
- `SEND_TO_SLACK_OUTPUT` - File path to write JSON output instead of stdout
- `SHOW_METADATA` - Set to `false` to disable metadata output (default: `true`)
- `SHOW_PAYLOAD` - Set to `false` to exclude payload from metadata (default: `true`)
- `SKIP_SLACK_API_CHECK` - Set to `true` to skip API connectivity check in health check mode

## Debug Mode

Enable debug mode by setting `params.debug: true` in your payload. When enabled, debug mode provides enhanced visibility for troubleshooting:

### Features

- Sanitized Payload Logging: Logs the input payload to stderr with sensitive authentication tokens redacted as `[REDACTED]`. This allows you to inspect the payload structure without exposing credentials.
- Automatic Metadata Override: Forces `SHOW_METADATA` and `SHOW_PAYLOAD` to `true`, ensuring full metadata output regardless of environment variable settings.

### Usage

```json
{
  "source": {
    "slack_bot_user_oauth_token": "xoxb-your-token"
  },
  "params": {
    "channel": "notifications",
    "debug": true,
    "blocks": [...]
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
    "blocks": [...]
  }
}
```

Debug mode redacts authentication tokens but still logs the payload structure.

## Features

- Slack Block Kit with either native `type` blocks or keyed format
- File upload support with automatic image or rich-text block creation
- Crossposting with permalinks and optional custom text
- Thread replies and thread creation for multi-block messages
- Input flexibility: stdin, `-f|--file`, `params.raw`, or `params.from_file`
- Dry-run mode, dependency health check, and rich validation output
- Debug mode with sanitized payload logging for troubleshooting
- Legacy attachments for colored blocks and tables where Slack allows
- Interactive button components with the optional Python server
- Concourse CI resource type support for pipeline notifications

## Requirements

### Runtime Dependencies

- <strong>Bash 3.1</strong> or later (scripts include version checks and will fail fast with clear error messages)
- `jq` - [jqlang](https://github.com/jqlang/jq) for JSON processing
- `curl` - [curl](https://curl.se/) for HTTP requests
- `gettext` - [GNU gettext](https://www.gnu.org/software/gettext/) for msgfmt tooling

### Interactive Components Dependencies

- <strong>Python 3.9</strong> or later (for interactive button handling)
- <strong>Flask 3.0.0</strong> or later (for web server)
- <strong>requests 2.31.0</strong> or later (for HTTP requests to Slack API)
- <strong>Docker</strong> (for ngrok integration, optional)

### Slack Configuration

Slack bot token with appropriate OAuth scopes:

- `channels:read`, `channels:write` - Channel access
- `files:write`, `files:read` - File operations
- `groups:read`, `im:read` - Group and DM access
- `users:read` - User information

See [Slack API Scopes](https://api.slack.com/scopes) for complete documentation.

## Usage

`send-to-slack` expects a JSON payload. Provide it on stdin or with `-f|--file`. You can also embed the payload through `params.raw` (stringified JSON) or `params.from_file` (path to a JSON file). When the `source` object is missing, the tool falls back to the environment variables `SLACK_BOT_USER_OAUTH_TOKEN`, `CHANNEL`, and `DRY_RUN`.

### Payload Structure

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
    "crosspost": {
      "channels": ["#channel1", "#channel2"],
      "text": "See the original message"
    },
    "raw": "{\"source\": {...}, \"params\": {...}}",
    "from_file": "./payload.json"
  }
}
```

### Required Parameters

- `source.slack_bot_user_oauth_token` or `SLACK_BOT_USER_OAUTH_TOKEN`
- `params.channel` or `CHANNEL`
- `params.blocks`

### Optional Parameters

- `params.debug` - Set to `true` to enable debug mode (default: `false`). When enabled:
  - Logs sanitized input payload (with auth tokens redacted) to stderr for debugging
  - Overrides `SHOW_METADATA` and `SHOW_PAYLOAD` to `true` regardless of environment variable settings
- `params.text` - Fallback text for notifications (max 40,000 characters)
- `params.dry_run` - Set to `true` to validate without sending (default: `false`)
- `params.thread_ts` - Thread timestamp or Slack message permalink (see Threading)
- `params.create_thread` - Set to `true` to create a new thread (see Threading)
- `params.crosspost` - Crosspost configuration (see Crossposting)
- `params.raw` - JSON string that replaces the `params` object
- `params.from_file` - Path to JSON that replaces the `params` object
- `params.blocks` - Array of block configurations

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

Named colors on a block (`danger`, `success`, `warning`) or a `table` block are wrapped in legacy attachments automatically.

### Message Limits

- Maximum 50 blocks per message (including blocks inside attachments)
- Maximum 20 attachments per message
- Maximum 40,000 characters for `text` fields

## Threading

`create_thread` and `thread_ts` are mutually exclusive. `thread_ts` can be supplied as either a Slack timestamp or a permalink; the tool converts permalinks automatically. When `create_thread` is `true` and multiple blocks are present, the first block is sent as the parent message and the remaining blocks are sent as the thread reply.

### Replying to Existing Threads

Provide `thread_ts` with the parent message timestamp. Extract from the permalink (the shareable url): `p1763161862880069` becomes `1763161862.880069` with the decimal inserted after 10 digits.

```json
{
  "params": {
    "channel": "notifications",
    "thread_ts": "1763161862.880069",
    "blocks": [...]
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
    "blocks": [...]
  }
}
```

## Crossposting

The program supports crossposting messages to additional channels after the initial notification is sent. When crossposting is enabled, the permalink to the original message is automatically appended to each crosspost.

### Crosspost Configuration

Add a `crosspost` object to your `params` section:

```json
{
  "params": {
    "channel": "#main-channel",
    "blocks": [...],
    "crosspost": {
      "channels": ["#channel1", "#channel2"],
      "text": "See the original message"
    }
  }
}
```

### Crosspost Parameters

- `crosspost.channels` (required) - Channel name or ID; accepts a string or array
- `crosspost.text` (optional) - Text to include in the crosspost message, defaults to `This is an automated crosspost.`

### How It Works

1. The initial notification is sent to the channel specified in `params.channel`
2. After successful delivery, the permalink to the original message is retrieved
3. For each channel in `crosspost.channels`, a new message is created with:
   - A rich-text block containing `crosspost.text` followed by the permalink
   - The message is sent to the specified channel
4. If a crosspost fails for a specific channel, the error is logged but processing continues for remaining channels

## File Uploads

Use the `file` block type to upload files through Slack's `files.getUploadURLExternal` flow.

- Required: `path` to the file and a resolvable `channel` (from `params.channel` or `CHANNEL`)
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

### Local Concourse Development

```bash
make concourse-up            # Start local Concourse server
make concourse-down          # Stop local Concourse server
make concourse-load-examples # Load example pipelines
```

Required environment variables for `concourse-load-examples`:

- `SLACK_BOT_USER_OAUTH_TOKEN` - Slack bot OAuth token
- `CHANNEL` - Target Slack channel for example pipelines

### Development Dependencies

- `bats` - [Bash Automated Testing System](https://github.com/bats-core/bats-core)
- `shfmt` - [Shell script formatter](https://github.com/mvdan/sh)
- `shellcheck` - [Shell script static analysis](https://github.com/koalaman/shellcheck)

## Contributing

Contributions are not welcome at this time.

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.

## References

- [Slack Block Kit](https://api.slack.com/block-kit) - Official documentation for Slack message formatting
- [Slack Web API](https://api.slack.com/web) - Reference for Slack API endpoints and methods
- [Concourse Resource Types](https://concourse-ci.org/resource-types.html) - Concourse CI resource type documentation
