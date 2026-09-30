---
name: list-events
description: Lists calendar events for a date (default: today).
---

# List Events

## Instructions
To list events, you must call the `list-events` tool with the following exact parameters:
- `toolName`: "list-events"
- `input`: A JSON string containing the field "date".

Rules for "date":
- For today, OMIT the field (send `{}`).
- For other days, use YYYY-MM-DD, or the words "tomorrow" / "yesterday".
- Never guess a date. Use the "Current date" line in the conversation as reference.