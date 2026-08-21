# Concourse

Use `send-to-slack` as a Concourse CI [resource type](https://concourse-ci.org/resource-types.html) to send Slack messages from pipelines.

## Quick start

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

Webhook resources use `source.webhook_url` instead of `slack_bot_user_oauth_token`. Incoming Webhooks do not support file uploads, crosspost, `params.thread.replies`, or `params.message_ts` / `params.message_ts_file` updates; see [Payload Reference](payload-reference.md) and [Message Management](features/message-management.md).

## Examples

Executable pipelines live under [examples/](../examples/). Catalog and `fly set-pipeline` usage: [Examples catalog](../examples/README.md). Highlighted coverage:

- Block Kit formatting and native `type` format
- File uploads
- Thread replies via `params.thread.replies` ([thread-replies.yaml](../examples/thread-replies.yaml))
- Message update via `params.message_ts` / `params.message_ts_file` ([update-message.yaml](../examples/update-message.yaml))
- Bot identity ([bot-identity.yaml](../examples/bot-identity.yaml))
- Incoming Webhooks ([webhook-slack.yaml](../examples/webhook-slack.yaml), [webhook-no-channel.yaml](../examples/webhook-no-channel.yaml))
- Interactive components ([actions.yaml](../examples/actions.yaml))

## Local Concourse workflow

```bash
make concourse-start
make concourse-stop
```

Load every `examples/*.yaml` pipeline:

```bash
export SLACK_BOT_USER_OAUTH_TOKEN="xoxb-your-token"
export CHANNEL="#your-channel"
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/<workspace-id>/<app-id>/<token>"
export SIDE_CHANNEL=""
export EPHEMERAL_USER=""
make concourse-load-examples
```

`make concourse-load-examples` passes these into `fly set-pipeline -v` for each example file:

| Variable                     | Role                                                                         |
| ---------------------------- | ---------------------------------------------------------------------------- |
| `SLACK_BOT_USER_OAUTH_TOKEN` | Web API bot token for most examples                                          |
| `CHANNEL`                    | Primary Slack channel (`channel` pipeline var)                               |
| `SIDE_CHANNEL`               | Secondary channel where used; may be empty                                   |
| `SLACK_WEBHOOK_URL`          | Incoming Webhook URL for webhook examples; may be empty if you skip those    |
| `EPHEMERAL_USER`             | Slack user ID for [ephemeral.yaml](../examples/ephemeral.yaml); may be empty |
| `TAG`                        | Resource image tag; defaults to the repo `VERSION` file when unset           |

Run every example job end-to-end:

```bash
make concourse-run-all-examples
```

That target restarts Concourse and runs `./ci/build.sh` first. Prerequisites, skip lists, and script flags: [CI Scripts](../ci/README.md). If `SLACK_WEBHOOK_URL` is unset, `webhook-slack/notify-via-slack-webhook` is skipped automatically.

## Resource type implementation

Scripts under `concourse/resource-type/scripts/`:

- `check` - version check (not applicable for this resource)
- `in` - fetch version (not applicable for this resource)
- `out` - send a message to Slack

Tests: `concourse/resource-type/tests/`. Interface reference: [Concourse Resource Types](https://concourse-ci.org/implementing-resource-types.html#implementing-resource-types).
