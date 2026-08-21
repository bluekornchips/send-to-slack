# Concourse CI Integration

This project can be used as a Concourse CI [resource type](https://concourse-ci.org/resource-types.html) to send messages to Slack from your pipelines.

Full guide: [docs/concourse.md](../docs/concourse.md). Example catalog: [examples/README.md](../examples/README.md).

## Quick start

Configure the resource type in your pipeline:

```yaml
resource_types:
  - name: slack-notification
    type: registry-image
    source:
      repository: sunflowersoftware/send-to-slack
      tag: ((TAG))

resources:
  - name: slack-notification
    type: slack-notification
    source:
      slack_bot_user_oauth_token: ((SLACK_BOT_USER_OAUTH_TOKEN))

jobs:
  - name: notify
    plan:
      - put: slack-notification
        params:
          channel: notifications
          blocks:
            - section:
                type: text
                text:
                  type: mrkdwn
                  text: "*Build completed* successfully!"
```

Webhook resources use `source.webhook_url` instead of `slack_bot_user_oauth_token`. Incoming Webhooks do not support file uploads, crosspost, `params.thread.replies`, or `params.message_ts` / `params.message_ts_file` updates in this tool; see [docs/payload-reference.md](../docs/payload-reference.md) and [docs/features/message-management.md](../docs/features/message-management.md).

## Resource type implementation

The resource type implementation lives under `concourse/resource-type/scripts/` as `check.sh`, `in.sh`, and `out.sh`, with tests under `concourse/resource-type/tests/`:

- `check` - Checks for new versions (not applicable for this resource)
- `in` - Retrieves a version (not applicable for this resource)
- `out` - Sends a message to Slack

See the [Concourse Resource Types Documentation](https://concourse-ci.org/implementing-resource-types.html#implementing-resource-types) for more details.
