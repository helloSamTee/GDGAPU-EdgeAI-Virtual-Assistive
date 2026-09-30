---
name: create-calendar-event
description: Creates a new event in the user's Google Calendar.
argument-hint: '{"title":"Meeting", "date":"YYYY-MM-DD", "startTime":"HH:MM", "endTime":"HH:MM"}'
---

# Create Calendar Event
Creates a new event in the user's primary Google Calendar. 

**CRITICAL RULES:**
You MUST use the exact JSON keys: `title`, `date`, `startTime`, and `endTime`. Do not use spaces or capital letters for the keys.
- `date`: Must be YYYY-MM-DD format.
- `startTime`: Must be 24-hour HH:MM format.
- `endTime`: Must be 24-hour HH:MM format.

Rules for "date":
- For today, OMIT the field (send `{}`).
- For other days, use YYYY-MM-DD, or the words "tomorrow" / "yesterday".
- Never guess a date. Use the "Current date" line in the conversation as reference.