# Concourse CI Integration

This project can be used as a Concourse CI [resource type](https://concourse-ci.org/resource-types.html) to send messages to Slack from your pipelines.

## Quick Start

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

## Examples

See the [examples/](../examples/) directory for complete Concourse pipeline examples, including:

- Basic message sending
- Block Kit formatting
- File uploads
- Thread replies (multiple messages in a thread)
- Updating an existing message with `params.message_ts` and `chat.update` ([update-message.yaml](../examples/update-message.yaml))
- Per-message bot display name and avatar ([bot-identity.yaml](../examples/bot-identity.yaml))
- Incoming Webhooks ([webhook-slack.yaml](../examples/webhook-slack.yaml))
- Interactive components

Webhook resources use `source.webhook_url` instead of `slack_bot_user_oauth_token`. Incoming Webhooks do not support file uploads, crosspost, thread replies, or `params.message_ts` updates in this tool; see the main [README.md](../README.md).

## Local Development

### Running Concourse Locally

Start a local Concourse server:

```bash
make concourse-up
```

Stop the server:

```bash
make concourse-down
```

### Loading Example Pipelines

Load example pipelines into your local Concourse instance:

```bash
export SLACK_BOT_USER_OAUTH_TOKEN="xoxb-your-token"
export CHANNEL="#your-channel"
# Required for examples/webhook-slack.yaml: replace with your real Incoming Webhook URL from Slack.
export SLACK_WEBHOOK_URL="https://hooks.slack.com/services/<workspace-id>/<app-id>/<token>"
# Optional secondary channel for pipelines that reference side_channel.
export SIDE_CHANNEL=""
# Optional Slack user ID for examples/ephemeral.yaml.
export EPHEMERAL_USER=""
make concourse-load-examples
```

`make concourse-load-examples` passes `SLACK_BOT_USER_OAUTH_TOKEN`, `CHANNEL`, `SIDE_CHANNEL`, `SLACK_WEBHOOK_URL`, `EPHEMERAL_USER`, and `TAG` into `fly set-pipeline -v` for each `examples/*.yaml` file. `TAG` defaults to the value in the repo `VERSION` file when you do not export `TAG`.

To run every example pipeline end-to-end in one go, use `make concourse-run-all-examples`; see [ci/README.md](../ci/README.md). If `SLACK_WEBHOOK_URL` is unset, the webhook example job is skipped automatically.

## Resource Type Implementation

The resource type implementation lives under `concourse/resource-type/scripts/` as `check.sh`, `in.sh`, and `out.sh`, with tests under `concourse/resource-type/tests/`. It follows the [Concourse resource type interface](https://concourse-ci.org/implementing-resource-types.html#implementing-resource-types):

- `check` - Checks for new versions (not applicable for this resource)
- `in` - Retrieves a version (not applicable for this resource)
- `out` - Sends a message to Slack

See the [Concourse Resource Types Documentation](https://concourse-ci.org/implementing-resource-types.html#implementing-resource-types) for more details on implementing resource types.
