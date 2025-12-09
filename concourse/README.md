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
      tag: v0.1.2

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
- Interactive components

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
make concourse-load-examples
```

This will load all YAML files from the `examples/` directory as pipelines.

## Resource Type Implementation

The resource type implementation is located in `concourse/resource-type/`. It follows the [Concourse resource type interface](https://concourse-ci.org/implementing-resource-types.html#implementing-resource-types):

- `check` - Checks for new versions (not applicable for this resource)
- `in` - Retrieves a version (not applicable for this resource)
- `out` - Sends a message to Slack

See the [Concourse Resource Types Documentation](https://concourse-ci.org/implementing-resource-types.html#implementing-resource-types) for more details on implementing resource types.
