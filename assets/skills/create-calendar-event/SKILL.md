---
name: create-calendar-event
description: Creates a new event in the user's Google Calendar.
argument-hint: '{"title":"Meeting", "date":"YYYY-MM-DD", "startTime":"HH:MM", "endTime":"HH:MM"}'
---

# Create Calendar Event
Creates a new event in the user's primary Google Calendar. 

**CRITICAL RULES:**
You MUST use the exact JSON keys: `title`, `date`, `startTime`, and `endTime`. Use these keys exactly as written, including the capital T in `startTime` and `endTime`. Do not add spaces.
- `date`: Must be YYYY-MM-DD format.
- `startTime`: Must be 24-hour HH:MM format.
- `endTime`: Must be 24-hour HH:MM format.