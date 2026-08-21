# CLI Reference

Command line options, environment variables, health check, and debug mode for `send-to-slack`.

## CLI usage

- Reads JSON from stdin when no file is provided.
- Use `-f`, `-file`, or `--file` to point at a payload file.
- Use `-v` or `--version` to display version information and exit.
- Use `-h` or `--help` to display usage information and exit.
- Use `--health-check` to validate `jq`, `curl`, and optional Slack API connectivity without sending a message. It does not check `envsubst`; see [Getting Started](getting-started.md) prerequisites.
- Emits Concourse-style JSON (`version`, `metadata`) to stdout unless `SEND_TO_SLACK_OUTPUT` is set.

## Health check

Use `--health-check` to validate dependencies `jq` and `curl` and optionally test Slack Web API connectivity if `SLACK_BOT_USER_OAUTH_TOKEN` is set. There is no separate probe for Incoming Webhook URLs. The check does not verify `envsubst`; payloads that use variable interpolation in blocks still need `envsubst` on PATH at send time. Returns exit code 0 on success, 1 on failure. Skips the API check if `DRY_RUN` or `SKIP_SLACK_API_CHECK` is set.

## Environment variables

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

## Debug mode

Enable debug mode by setting `params.debug: true` in your payload. When enabled, debug mode provides enhanced visibility for troubleshooting:

### Features

- Sanitized Payload Logging: Logs the input payload to stderr with sensitive authentication tokens redacted as `[REDACTED]`. This allows you to inspect the payload structure without exposing credentials.
- Automatic Metadata Override: Forces `SHOW_METADATA` and `SHOW_PAYLOAD` to `true`, and sets `LOG_VERBOSE` to `true`, regardless of prior environment variable settings.
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

When debug mode is enabled, you will see output like:

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
