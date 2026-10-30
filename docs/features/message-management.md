# Message Management

Update messages, crosspost to other channels, and upload files. Web API only; Incoming Webhooks skip crosspost, and reject updates and `file` blocks.

Related: [Payload Reference](../payload-reference.md), [Threading](threading.md), [Examples catalog](../../examples/README.md)

## Updating messages

Set `params.message_ts`, or leave it empty and set `params.message_ts_file` to a file containing a `ts`. The tool calls `chat.update` with that timestamp.

- Requires Web API delivery and `params.channel` in the JSON (no `CHANNEL` env fallback)
- Skips new post, `params.thread.replies`, and crosspost for that run
- Output may include `version.message_ts` when the API returns a `ts`

Example: [examples/update-message.yaml](../../examples/update-message.yaml) (post, write `message_ts` to a file, update via `message_ts_file`).

## Crossposting

After a successful primary send, post related messages to more channels via `params.crosspost`. Webhooks skip crosspost.

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
              "text": "See the original announcement"
            }
          }
        }
      ]
    }
  }
}
```

| Field                                      | Notes                                                |
| ------------------------------------------ | ---------------------------------------------------- |
| `crosspost.channel` / `crosspost.channels` | Channel name or ID; string or array                  |
| `crosspost.blocks`                         | Same block formats as `params.blocks`                |
| `crosspost.text`                           | Optional fallback text                               |
| `crosspost.no_link`                        | `true` to skip the automatic permalink context block |

Remaining crosspost fields are passed through as message params. `$NOTIFICATION_PERMALINK` is available in crosspost blocks via `envsubst`. Per-channel failures are logged and other channels continue; the run exits non-zero if any channel failed.

Example: [examples/crosspost.yaml](../../examples/crosspost.yaml).

## File uploads

Use a `file` block (`files.getUploadURLExternal` plus `files.completeUploadExternal`). Requires `path` and a resolvable channel (`params.channel` or `CHANNEL`). Token needs `files:write`.

The file is shared into the channel as a snippet or file card on the same message as sibling blocks. That is how a context header and a `.md` preview land together. Images are file cards, not image blocks. `.md` / `.markdown` files set `snippet_type=markdown` so Slack renders a markdown snippet.

`file` blocks cannot be used with Incoming Webhooks, `params.ephemeral_user`, or `params.message_ts` / `params.message_ts_file`.

| Field                              | Notes                                           |
| ---------------------------------- | ----------------------------------------------- |
| `path`                             | Local file path (required)                      |
| `title`                            | Display title (optional; defaults to filename)  |
| `interpolate_file_contents_to_var` | Export file contents to this env var (optional) |

Max size 1 GB.

Examples: [file-upload.yaml](../../examples/file-upload.yaml), [file-blocks.yaml](../../examples/file-blocks.yaml).
