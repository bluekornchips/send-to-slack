# TODO

## Slack API Features

### reply_broadcast

Send a thread reply that also appears in the main channel, visible to all members regardless of thread subscription.

- Use case: CI pipelines that reply in a thread for detail but need visibility of the final status (pass/fail) in the channel itself.
- Param: `params.reply_broadcast: true`
- Applies to: Web API delivery only. Ignored for webhook delivery.
- Ref: [chat.postMessage - reply_broadcast](https://api.slack.com/methods/chat.postMessage)

---

### Retry-After header

When Slack returns `rate_limited`, it includes a `Retry-After` header specifying the exact number of seconds to wait before retrying. The current retry loop uses fixed exponential backoff and ignores this header.

- Use case: Reliable, compliant rate limit handling. Avoids retrying too early, which causes further throttling, or waiting too long, which wastes pipeline time.
- Applies to: All API delivery paths.
- Ref: [Slack Rate Limits](https://api.slack.com/docs/rate-limits)

---

### unfurl_links / unfurl_media

Control whether Slack automatically expands URLs in the message into rich link previews. Currently these cannot be set and Slack defaults to expanding links.

- Use case: CI notification messages with URLs, such as build logs or PR links, where link unfurling creates visual noise.
- Params: `params.unfurl_links: false`, `params.unfurl_media: false`
- Applies to: Web API delivery only.
- Ref: [chat.postMessage - unfurling](https://api.slack.com/methods/chat.postMessage)

---

### reactions.add

Add one or more emoji reactions to the sent message after delivery. The message `ts` is already captured from the API response and exposed in Concourse metadata.

- Use case: Pipelines that add a checkmark on success and an X on failure as a fast visual indicator without sending a follow-up message.
- Param: `params.reactions: ["white_check_mark"]`
- Applies to: Web API delivery only. Not supported for ephemeral messages or webhook delivery.
- Requires scope: `reactions:write`
- Ref: [reactions.add](https://api.slack.com/methods/reactions.add)

---

### chat.scheduleMessage

Schedule a message for delivery at a future time using a Unix timestamp. Slack holds and delivers the message at the specified time.

- Use case: Scheduled maintenance announcements, end-of-day summaries, or reminders timed to a deployment window.
- Param: `params.schedule_at` as an ISO-8601 datetime or Unix epoch integer.
- Applies to: Web API delivery only.
- Requires scope: `chat:write`
- Ref: [chat.scheduleMessage](https://api.slack.com/methods/chat.scheduleMessage)

---

## Block Kit

### Actions block elements beyond button

The actions block currently only supports `button` elements. Slack supports additional interactive elements inside actions blocks.

- Use case: Dropdowns for selecting environments or branches, date pickers for scheduling, and overflow menus for grouped actions, all inside a single actions block.
- Missing element types: `static_select`, `multi_static_select`, `overflow`, `datepicker`, `timepicker`, `checkboxes`, `radio_buttons`
- Ref: [Actions block elements](https://docs.slack.dev/reference/block-kit/blocks/actions-block)

---

