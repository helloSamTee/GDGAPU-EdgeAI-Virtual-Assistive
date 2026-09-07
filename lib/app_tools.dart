import 'package:flutter_gemma/flutter_gemma.dart';

// Tool schemas passed to InferenceChat so the model knows what it can call,
// with what arguments, and when.
class AppTools {
  static final createEventTool = Tool(
    name: 'create_calendar_event',
    description: "Creates a new event on the user's Google Calendar.",
    parameters: {
      'type': 'object',
      'properties': {
        'title': {'type': 'string', 'description': 'Title of the event.'},
        'date': {
          'type': 'string',
          'description': 'Event date in YYYY-MM-DD format.',
        },
        'startTime': {
          'type': 'string',
          'description': 'Start time in HH:mm 24-hour format.',
        },
        'endTime': {
          'type': 'string',
          'description': 'End time in HH:mm 24-hour format.',
        },
      },
      'required': ['title', 'date', 'startTime', 'endTime'],
    },
  );

  static final listEventsTool = Tool(
    name: 'list_events',
    description:
        'Lists all calendar events for a specific date. Defaults to '
        "today if no date is given.",
    parameters: {
      'type': 'object',
      'properties': {
        'date': {
          'type': 'string',
          'description':
              'Date in YYYY-MM-DD format. Optional, defaults to today.',
        },
      },
      'required': <String>[],
    },
  );

  static final readLatestEmailTool = Tool(
    name: 'read_latest_email',
    description:
        "Reads the subject, sender, and snippet of the user's most "
        'recent email.',
    parameters: {
      'type': 'object',
      'properties': <String, dynamic>{},
      'required': <String>[],
    },
  );

  static List<Tool> get all => [
    createEventTool,
    listEventsTool,
    readLatestEmailTool,
  ];
}
