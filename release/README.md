# Release Package

Self-contained `send-to-slack` script for one-liner curl execution.

## Build

```bash
./build.sh
```

## Dependencies

- `bash`
- `curl`
- `jq`
- `gettext` (provides `envsubst`)

## Usage

### One-liner curl + execute

```bash
curl -sL https://raw.githubusercontent.com/bluekornchips/send-to-slack/main/release/send-to-slack | \
  SLACK_BOT_USER_OAUTH_TOKEN="xoxb-..." bash -s <<< \
  '{"params":{"channel":"#general","blocks":[{"header":{"text":{"type":"plain_text","text":"Hello"}}}]}}'
```

### Direct execution

```bash
export SLACK_BOT_USER_OAUTH_TOKEN="xoxb-..."
./send-to-slack -f payload.json
```

### Piped JSON

```bash
echo '{"params":{"channel":"#general","blocks":[{"section":{"type":"text","text":{"type":"mrkdwn","text":"Hello *world*"}}}]}}' | \
  SLACK_BOT_USER_OAUTH_TOKEN="xoxb-..." ./send-to-slack
```
