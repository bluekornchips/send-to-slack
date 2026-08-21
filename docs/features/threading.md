# Threading

Reply to existing threads and send follow up replies. Incoming Webhook delivery skips `params.thread.replies` and threaded sends that depend on `params.thread_ts`.

`params.thread_ts` can be a Slack timestamp or a message permalink; the tool converts permalinks automatically.

## Replying to an existing thread

Set `params.thread_ts` to the parent message timestamp. From a Slack permalink, `p1763161862880069` becomes `1763161862.880069` with the decimal inserted after 10 digits.

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

## Multiple replies with `params.thread.replies`

Use `params.thread.replies` to send additional messages as separate replies in the same thread. Each array entry must include a non-empty `blocks` array.

Thread anchor rules:

- If `params.thread_ts` is set, the primary `params.blocks` message and each reply land in that existing thread.
- If `params.thread_ts` is omitted, the primary message is posted to the channel, then each reply uses that new message `ts` as the thread anchor.

See [examples/thread-replies.yaml](../../examples/thread-replies.yaml).

```json
{
  "params": {
    "channel": "notifications",
    "blocks": [
      {
        "section": {
          "type": "text",
          "text": { "type": "mrkdwn", "text": "Parent" }
        }
      }
    ],
    "thread": {
      "replies": [
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
}
```

Per-reply send failures are logged and the overall run continues. Bot identity fields on the parent (`username`, `icon_emoji`, `icon_url`) are inherited by replies.
