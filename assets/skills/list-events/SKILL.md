---
name: list-events
description: Lists the user's Google Calendar events for a given date. Defaults to today if no date is given.
metadata:
  mcp-server-url: http://127.0.0.1:8765/mcp
---
# List Events

## Instructions
Call the `list_events` MCP tool. Pass a `date` argument in YYYY-MM-DD
format if the user names a specific day; omit it to default to today.