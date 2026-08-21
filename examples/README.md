# Examples

Concourse pipeline examples for supported Slack Block Kit block types and features. Payload parameters and limits: [docs/payload-reference.md](../docs/payload-reference.md). Official Block Kit field docs: [Slack Block Kit](https://docs.slack.dev/reference/block-kit).

## Available examples

| Example                                            | Description                                                                           | Related guide                                                                                 |
| -------------------------------------------------- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| [acceptance.yaml](acceptance.yaml)                 | Acceptance test examples                                                              | [Payload Reference](../docs/payload-reference.md), [Threading](../docs/features/threading.md) |
| [blocks-from-file.yaml](blocks-from-file.yaml)     | Load individual blocks from JSON files                                                | [Payload Reference](../docs/payload-reference.md)                                             |
| [bot-identity.yaml](bot-identity.yaml)             | Per-message `username`, `icon_emoji`, and `icon_url`; requires `chat:write.customize` | [Payload Reference](../docs/payload-reference.md)                                             |
| [actions.yaml](actions.yaml)                       | Interactive action blocks                                                             | [Interactive Components](../python/README.md)                                                 |
| [context.yaml](context.yaml)                       | Context block examples                                                                | [Payload Reference](../docs/payload-reference.md)                                             |
| [crosspost.yaml](crosspost.yaml)                   | Crossposting to multiple channels                                                     | [Message Management](../docs/features/message-management.md)                                  |
| [divider.yaml](divider.yaml)                       | Divider block examples                                                                | [Payload Reference](../docs/payload-reference.md)                                             |
| [ephemeral.yaml](ephemeral.yaml)                   | `chat.postEphemeral` via `params.ephemeral_user`                                      | [Payload Reference](../docs/payload-reference.md)                                             |
| [file-blocks.yaml](file-blocks.yaml)               | File block variations                                                                 | [Message Management](../docs/features/message-management.md)                                  |
| [file-upload.yaml](file-upload.yaml)               | File upload examples                                                                  | [Message Management](../docs/features/message-management.md)                                  |
| [header.yaml](header.yaml)                         | Header block examples                                                                 | [Payload Reference](../docs/payload-reference.md)                                             |
| [image.yaml](image.yaml)                           | Image block examples                                                                  | [Payload Reference](../docs/payload-reference.md)                                             |
| [markdown.yaml](markdown.yaml)                     | Markdown block examples                                                               | [Payload Reference](../docs/payload-reference.md)                                             |
| [rich-text.yaml](rich-text.yaml)                   | Rich text block examples                                                              | [Payload Reference](../docs/payload-reference.md)                                             |
| [section.yaml](section.yaml)                       | Section block examples                                                                | [Payload Reference](../docs/payload-reference.md)                                             |
| [slack-native.yaml](slack-native.yaml)             | Slack native `type` format end to end                                                 | [Payload Reference](../docs/payload-reference.md)                                             |
| [table.yaml](table.yaml)                           | Table block examples                                                                  | [Payload Reference](../docs/payload-reference.md)                                             |
| [thread-replies.yaml](thread-replies.yaml)         | Multiple replies via `params.thread.replies`                                          | [Threading](../docs/features/threading.md)                                                    |
| [update-message.yaml](update-message.yaml)         | Post then update with `params.message_ts` / `params.message_ts_file`                  | [Message Management](../docs/features/message-management.md)                                  |
| [video.yaml](video.yaml)                           | Video block examples                                                                  | [Payload Reference](../docs/payload-reference.md)                                             |
| [webhook-slack.yaml](webhook-slack.yaml)           | Incoming Webhook delivery, no bot token                                               | [Getting Started](../docs/getting-started.md)                                                 |
| [webhook-no-channel.yaml](webhook-no-channel.yaml) | Incoming Webhook with no `params.channel`                                             | [Getting Started](../docs/getting-started.md)                                                 |

## Formats

The tool accepts both the keyed format (`{ "section": { ... } }`) and Slack's native `type` format (`{ "type": "section", ... }`). Most examples use the keyed format for readability; `slack-native.yaml` shows the native format across all block types. Details: [Payload Reference](../docs/payload-reference.md).

## Running the examples

These files are Concourse pipelines that use the `sunflowersoftware/send-to-slack` resource type. Pass the variables each file expects, for example:

```bash
fly -t <target> set-pipeline \
  -p send-to-slack-demo \
  -c examples/acceptance.yaml \
  -v SLACK_BOT_USER_OAUTH_TOKEN=<token> \
  -v channel=<channel> \
  -v side_channel=<secondary-or-empty> \
  -v TAG=<image-tag> \
  -v SLACK_WEBHOOK_URL=<webhook-or-empty> \
  -v ephemeral_user=<slack-user-id-or-empty>
```

`webhook-slack.yaml` and `webhook-no-channel.yaml` only need `SLACK_WEBHOOK_URL` and `TAG`. See each file for the exact `((VAR))` names. Pipelines that use the Web API need `SLACK_BOT_USER_OAUTH_TOKEN` and `channel`. `ephemeral.yaml` also needs `ephemeral_user`, a member user ID such as `U012AB3CD`.

Local Concourse load and run-all workflow: [docs/concourse.md](../docs/concourse.md). End-to-end runner skip lists and script flags: [ci/README.md](../ci/README.md).
