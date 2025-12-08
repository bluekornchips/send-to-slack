# Send to Slack

A bash program designed to send [block kit content](https://docs.slack.dev/reference/block-kit) to Slack via the Slack Web API.

## Why bash?

Bash is lightweight, powerful, and easily integrated into existing workflows that can access the shell. Slack offers more robust and widely maintained integrations at their [slackapi](https://github.com/slackapi) org, but these kits are language specific. This project was designed to be included in projects that support multiple languages and want feature parity without relying on more than one toolkit.

Measure twice, send once.

## Installation

### One-Line Remote Installation

Install directly from the repository without cloning (recommended for containers and CI/CD):

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install-remote.sh)"
```

This installer will:
- Check for required prerequisites (bash 4.0+, curl, jq, git)
- Clone the repository temporarily
- Install to `/usr/local` by default (requires sudo)
- Clean up temporary files automatically

**Custom installation prefix:**

```bash
INSTALL_PREFIX=/opt /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install-remote.sh)"
```

**Install from a specific branch:**

```bash
INSTALL_BRANCH=develop /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/install-remote.sh)"
```

The installer will fail gracefully if prerequisites are missing, making it safe to use in containers without needing to rebuild when the repository changes.

### System Installation

Install to system directory `/usr/local` (requires sudo):

```bash
git clone https://github.com/bluekornchips/send-to-slack.git
cd send-to-slack
sudo make install
```

Or use the installation script directly:

```bash
sudo ./install.sh /usr/local
```

### Custom Installation Prefix

Install to a custom location:

```bash
./install.sh /opt
```

### Uninstallation

```bash
sudo make uninstall
```

Or use the uninstall script directly:

```bash
sudo ./uninstall.sh /usr/local

```

## Container Image

The container image is available on Docker Hub as `sunflowersoftware/send-to-slack`.

```bash
docker pull sunflowersoftware/send-to-slack
```

### Development Usage

For development or testing without installation, you can use the script directly:

```bash
chmod +x send-to-slack.sh
./send-to-slack.sh
```

When running directly from the repository, the script will automatically detect its location and find source files.

## Quick Start

After installation, send a message to Slack by piping a JSON payload to the command:

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
            "type": "plain_text",
            "text": "Hello, world!"
          }
        }
      }
    ]
  }
}' | send-to-slack
```

If running from the repository without installation, use `./send-to-slack.sh` instead.

## Features

- Slack Block Kit support for rich message formatting
- File upload capabilities with automatic block type detection
- Legacy attachment support for colored blocks and tables
- Multiple input methods: JSON payload, raw JSON string, or file-based configuration
- Comprehensive error handling and validation
- Dry-run mode for testing configurations
- Thread reply support for organizing conversations
- Thread creation for multi-block messages
- Interactive button components with Python server integration
- Concourse CI resource type support

## Requirements

### Runtime Dependencies

- <strong>Bash 4.0</strong> or later
- `jq` - [jqlang](https://github.com/jqlang/jq) for JSON processing
- `curl` - [curl](https://curl.se/) for HTTP requests

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

The program reads JSON payload from `stdin` and sends messages to Slack. The payload structure consists of:

- `source` - Configuration object containing authentication credentials
- `params` - Parameters object containing message configuration

### Payload Structure

```json
{
  "source": {
    "slack_bot_user_oauth_token": "xoxb-your-token"
  },
  "params": {
    "channel": "channel-name-or-id",
    "blocks": [...],
    "text": "optional fallback text",
    "dry_run": false
  }
}
```

### Required Parameters

- `source.slack_bot_user_oauth_token` - Slack bot OAuth token
- `params.channel` - Slack channel name or ID

### Optional Parameters

- `params.blocks` - Array of block configurations (see [examples/](examples/) for block types)
- `params.text` - Fallback text for notifications (max 40,000 characters)
- `params.dry_run` - Set to `true` to validate without sending (default: `false`)
- `params.thread_ts` - Thread timestamp for replying to existing threads (see [Threading](#threading) section)
- `params.create_thread` - Set to `true` to create a new thread (see [Threading](#threading) section)
- `params.crosspost` - Crosspost configuration object (see [Crossposting](#crossposting) section)

## Threading

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

- `crosspost.channels` (required) - Array of channel names or IDs to crosspost to
- `crosspost.text` (required) - Text to include in the crosspost message

### How It Works

1. The initial notification is sent to the channel specified in `params.channel`
2. After successful delivery, the permalink to the original message is retrieved
3. For each channel in `crosspost.channels`, a new message is created with:
   - A rich-text block containing `crosspost.text` followed by the permalink
   - The message is sent to the specified channel
4. If a crosspost fails for a specific channel, the error is logged but processing continues for remaining channels

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
3. Convert to Tool Format: Transform the Builder's format to match this tool's payload structure:
   - Builder exports blocks directly in a `blocks` array
   - This tool expects blocks wrapped in `params.blocks` with block type keys (e.g., `{"section": {...}}`)
4. Use in Tool: Include the converted blocks in your payload

The Block Kit Builder exports blocks in Slack's native format. When used with our `send-to-slack` tool, you'll need to wrap blocks in the tool's expected format (see [README.md](../README.md#block-kit-builder) for conversion details).

## Development

### Running Tests

```bash
make test            # Run all tests
make test-all        # Run all tests (with smoke and acceptance flags)
make test-smoke      # Run smoke tests only
make test-acceptance # Run acceptance tests only
```

### Code Quality

```bash
make format  # Format shell scripts
make lint    # Lint shell scripts
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
