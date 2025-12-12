# Examples

This directory contains complete configuration examples for all supported Slack Block Kit block types and features.

## Available Examples

- [acceptance.yaml](acceptance.yaml) - Acceptance test examples
- [actions.yaml](actions.yaml) - Interactive action blocks
- [context.yaml](context.yaml) - Context block examples
- [crosspost.yaml](crosspost.yaml) - Crossposting to multiple channels with permalinks
- [divider.yaml](divider.yaml) - Divider block examples
- [file-blocks.yaml](file-blocks.yaml) - File block variations
- [file-upload.yaml](file-upload.yaml) - File upload examples
- [header.yaml](header.yaml) - Header block examples
- [image.yaml](image.yaml) - Image block examples
- [markdown.yaml](markdown.yaml) - Markdown block examples
- [rich-text.yaml](rich-text.yaml) - Rich text block examples
- [section.yaml](section.yaml) - Section block examples
- [slack-native.yaml](slack-native.yaml) - Using Slack's native `type` format end to end
- [table.yaml](table.yaml) - Table block examples
- [video.yaml](video.yaml) - Video block examples

## Formats

The tool accepts both the keyed format (`{ "section": { ... } }`) and Slack's native `type` format (`{ "type": "section", ... }`). Most examples use the keyed format for readability; `slack-native.yaml` shows the native format across all block types.

## Running the Examples

These files are Concourse pipelines that use the `sunflowersoftware/send-to-slack` resource type. Provide your Slack token and channel when setting a pipeline, for example:

```bash
fly -t <target> set-pipeline \
  -p send-to-slack-demo \
  -c examples/acceptance.yaml \
  -v SLACK_BOT_USER_OAUTH_TOKEN=<token> \
  -v channel=<channel>
```

## Supported Block Types

### Section Block

Text blocks with plain text or markdown formatting. Supports single text sections or fields arrays for side-by-side text display (up to 10 fields, each up to 2000 characters).

- Reference: [Slack Section Block Documentation](https://docs.slack.dev/reference/block-kit/blocks/section-block/)
- Example: [section.yaml](section.yaml)

### Header Block

Large title blocks for message headers.

- Reference: [Slack Header Block Documentation](https://docs.slack.dev/reference/block-kit/blocks/header-block)
- Example: [header.yaml](header.yaml)

### Image Block

Display images from URLs or Slack files. Supports optional title and block_id fields.

- Reference: [Slack Image Block Documentation](https://docs.slack.dev/reference/block-kit/blocks/image-block/)
- Example: [image.yaml](image.yaml)

Required Fields (one of the following):

- `image_url` - Publicly accessible image URL, OR
- `slack_file` - Slack file object with either:
  - `url` - Slack file URL (e.g., `https://files.slack.com/files-pri/...`)
  - `id` - Slack file ID (e.g., `F012345678`)
- `alt_text` - Plain text description for accessibility (max 2000 characters)

Optional Fields:

- `title` - Plain text title object (max 2000 characters)
- `block_id` - Unique identifier (max 255 characters)

Note: You cannot use both `image_url` and `slack_file` in the same image block.

### Divider Block

Visual separators between message sections.

- Reference: [Slack Divider Block Documentation](https://docs.slack.dev/reference/block-kit/blocks/divider-block)
- Example: [divider.yaml](divider.yaml)

### Context Block

Small text blocks for metadata and contextual information.

- Reference: [Slack Context Block Documentation](https://docs.slack.dev/reference/block-kit/blocks/context-block)
- Example: [context.yaml](context.yaml)

### Markdown Block

Markdown-formatted text blocks supporting up to 12,000 characters.

- Reference: [Slack Markdown Block Documentation](https://docs.slack.dev/reference/block-kit/blocks/markdown-block)
- Example: [markdown.yaml](markdown.yaml)

### Rich Text Block

Structured WYSIWYG content supporting up to 4,000 characters.

- Reference: [Slack Rich Text Block Documentation](https://docs.slack.dev/reference/block-kit/blocks/rich-text-block)
- Example: [rich-text.yaml](rich-text.yaml)

### Actions Block

Interactive buttons and elements for user interactions. Requires a web server to handle button click events.

- Reference: [Slack Actions Block Documentation](https://docs.slack.dev/reference/block-kit/blocks/actions-block)
- Example: [actions.yaml](actions.yaml)
- See [python/README.md](../python/README.md) for interactive components setup

### Table Block

Tabular data displayed using legacy attachments with color support.

- Reference: [Slack Table Block Documentation](https://docs.slack.dev/reference/block-kit/blocks/table-block/)
- Example: [table.yaml](table.yaml)

### Video Block

Embed videos directly into Slack messages. Supports provider information, author details, and optional description.

- Reference: [Slack Video Block Documentation](https://docs.slack.dev/reference/block-kit/blocks/video-block/)
- Example: [video.yaml](video.yaml)

Required Fields:

- `video_url` - Embeddable video URL
- `thumbnail_url` - Thumbnail image URL
- `alt_text` - Tooltip text for accessibility (max 2000 characters)
- `title` - Plain text title object (max 2000 characters)

Optional Fields:

- `title_url` - Hyperlink for title text
- `description` - Plain text description object (max 2000 characters)
- `author_name` - Author name (max 2000 characters)
- `provider_name` - Provider name e.g., "YouTube" (max 2000 characters)
- `provider_icon_url` - Provider icon URL
- `block_id` - Unique identifier (max 255 characters)

Video blocks require two configuration steps:

1. Bot Token Scopes: Add one of these scopes to your Slack app:

   - `links:read`
   - `links:write`
   - `links.embed:write`

   Go to: OAuth & Permissions > Bot Token Scopes

2. App Unfurl Domains: Add the video domain to your app's unfurl domains list:

   - Go to: App Settings > App Unfurl Domains
   - Add the domain (e.g., `youtube.com` for YouTube videos, `vimeo.com` for Vimeo)

   This step is critical - video blocks will not work without the domain in the unfurl list.

After making these changes, reinstall your app to your workspace to apply the updates.

Video URL Requirements:

- Must be publicly accessible
- Must return a 2xx HTTP status code
- Must be compatible with an embeddable iframe
- Cannot point to any Slack-related domain

### File Block

Upload files to Slack. Images create image blocks automatically; other file types create rich-text blocks.

- Reference: [Slack File Upload Documentation](https://docs.slack.dev/messaging/working-with-files/#upload)
- Example: [file-upload.yaml](file-upload.yaml)

#### File Upload Configuration

File blocks support the following parameters:

- `path` - Local path to the file to upload (required)
- `title` - Display title for the file in Slack (optional, defaults to filename)
- `interpolate_file_contents_to_var` - Environment variable name to export file contents to (optional)

## Message Limits

The program enforces Slack's message composition limits:

- Maximum <strong>50 blocks</strong> per message
- Maximum <strong>20 attachments</strong> per message
- Maximum <strong>40,000 characters</strong> for text fields

## Threading

Reply to existing threads with `thread_ts`. Create new threads with `create_thread: true` with the first block as the parent message, remaining blocks as the thread reply. See [acceptance.yaml](acceptance.yaml) for examples. If you only have one block, it will be sent as a regular message.

## Alternative Input Methods

### Raw JSON String

Provide a complete JSON payload as a string using `params.raw`:

```json
{
  "params": {
    "raw": "{\"source\": {...}, \"params\": {...}}"
  }
}
```

### Payload from File

Load payload configuration from an external file using `params.from_file`:

```json
{
  "params": {
    "from_file": "./my-payload.json"
  }
}
```
