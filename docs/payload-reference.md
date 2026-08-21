# Payload Reference

JSON shape, parameters, block formats, and limits for `send-to-slack`.

Related: [Getting Started](getting-started.md), [CLI Reference](cli-reference.md), [Threading](features/threading.md), [Message Management](features/message-management.md), [Examples catalog](../examples/README.md)

## Input

Provide JSON on stdin or with `-f|-file|--file`. You can also replace `params` via `params.raw` or `params.from_file` (see [Alternative inputs](#alternative-inputs)).

Delivery: set `source.slack_bot_user_oauth_token` (Web API) or `source.webhook_url` (Incoming Webhook). If both are set, the bot token wins. When `source` omits credentials, the tool uses `SLACK_BOT_USER_OAUTH_TOKEN` or `WEBHOOK_URL`, plus `CHANNEL` and `DRY_RUN` where applicable.

## Shape

Web API:

```json
{
  "source": {
    "slack_bot_user_oauth_token": "xoxb-your-token"
  },
  "params": {
    "channel": "channel-name-or-id",
    "blocks": [],
    "text": "optional fallback text"
  }
}
```

Incoming Webhook (`params.channel` optional when the hook is already bound to a channel):

```json
{
  "source": {
    "webhook_url": "https://hooks.slack.com/services/<workspace-id>/<app-id>/<token>"
  },
  "params": {
    "blocks": [
      {
        "type": "section",
        "text": { "type": "plain_text", "text": "Hello via webhook" }
      }
    ]
  }
}
```

## Required

| Delivery | Required                                                                                                                                     |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Web API  | `source.slack_bot_user_oauth_token` or `SLACK_BOT_USER_OAUTH_TOKEN`; `params.channel` or `CHANNEL`; `params.blocks` for typical new messages |
| Webhook  | `source.webhook_url` or `WEBHOOK_URL` (no bot token in effect); `params.blocks`; `channel` only if you need to set or override it            |

For `params.message_ts` / `params.message_ts_file` updates, `params.channel` must be in the JSON (no `CHANNEL` env fallback). See [Message Management](features/message-management.md).

## Optional params

| Param                    | Notes                                                                                                            |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------- |
| `params.blocks`          | Block array (native or keyed); see [Block formats](#block-formats) and [Examples catalog](../examples/README.md) |
| `params.text`            | Fallback text (max 40,000 characters)                                                                            |
| `params.dry_run`         | `true` to validate without sending                                                                               |
| `params.debug`           | `true` for sanitized payload logging; forces metadata/`LOG_VERBOSE` (see [CLI Reference](cli-reference.md))      |
| `params.thread_ts`       | Existing thread ts or permalink; see [Threading](features/threading.md)                                          |
| `params.thread.replies`  | Reply objects with non-empty `blocks`; see [Threading](features/threading.md)                                    |
| `params.crosspost`       | Extra channels after the primary send; see [Message Management](features/message-management.md)                  |
| `params.message_ts`      | `chat.update` timestamp (Web API; needs `params.channel` in JSON)                                                |
| `params.message_ts_file` | File whose contents are the update `ts` (used if `message_ts` empty)                                             |
| `params.ephemeral_user`  | `chat.postEphemeral` user ID (Web API only; no threads/crosspost/permalink)                                      |
| `params.username`        | Bot display name override (Web API; `chat:write.customize`; not webhook)                                         |
| `params.icon_emoji`      | Emoji avatar override (same constraints as `username`)                                                           |
| `params.icon_url`        | Image avatar override (same constraints as `username`)                                                           |
| `params.raw`             | JSON string that replaces all of `params`                                                                        |
| `params.from_file`       | Path to a JSON object that replaces all of `params`                                                              |

Bot identity example: [examples/bot-identity.yaml](../examples/bot-identity.yaml). Ephemeral: [examples/ephemeral.yaml](../examples/ephemeral.yaml).

`source.webhook_url` is ignored when a bot token selects Web API delivery.

## Block formats

Native:

```json
{ "type": "section", "text": { "type": "plain_text", "text": "Hello" } }
```

Keyed:

```json
{
  "section": {
    "type": "text",
    "text": { "type": "plain_text", "text": "Hello" }
  }
}
```

Block-level file load (single block or array; relative paths try `SEND_TO_SLACK_PAYLOAD_BASE_DIR`, then `PWD`):

```json
{ "from_file": "blocks.json" }
```

Named colors (`danger`, `success`, `warning`) and `table` blocks become legacy attachments. Worked demos: [Examples catalog](../examples/README.md). Field reference: [Slack Block Kit](https://docs.slack.dev/reference/block-kit).

## Alternative inputs

`params.raw` and `params.from_file` replace the `params` object only (channel, blocks, etc.), not a full `{ "source", "params" }` envelope:

```json
{
  "source": { "slack_bot_user_oauth_token": "xoxb-your-token" },
  "params": {
    "raw": "{\"channel\":\"notifications\",\"blocks\":[]}"
  }
}
```

```json
{
  "source": { "slack_bot_user_oauth_token": "xoxb-your-token" },
  "params": { "from_file": "./my-params.json" }
}
```

Mix inline blocks with block-level `from_file`:

```yaml
blocks:
  - header:
      text: { type: "plain_text", text: "Title" }
  - from_file: blocks.json
```

Worked example and fixtures: [examples/blocks-from-file.yaml](../examples/blocks-from-file.yaml), [examples/fixtures/](../examples/fixtures/).

## Limits

- 50 blocks per message (including blocks inside attachments)
- 20 attachments per message
- 40,000 characters for `text` fields
