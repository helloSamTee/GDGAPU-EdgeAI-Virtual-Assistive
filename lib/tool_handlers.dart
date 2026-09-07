import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

import 'google_auth_service.dart';

// Dispatches a FunctionCallResponse from the model to the matching Dart
// implementation, and returns a plain Map the model can read back as the
// tool's result.
class ToolHandlers {
  static Future<Map<String, dynamic>> handle(FunctionCallResponse call) {
    switch (call.name) {
      case 'create_calendar_event':
        return _createCalendarEvent(call.args);
      case 'list_events':
        return _listEvents(call.args);
      case 'read_latest_email':
        return _readLatestEmail();
      default:
        return Future.value({'error': 'Unknown tool: ${call.name}'});
    }
  }

  static Future<Map<String, dynamic>> _createCalendarEvent(
    Map<String, dynamic> args,
  ) async {
    try {
      final api = await GoogleAuthService.instance.getCalendarApi();

      final date = args['date'] as String;
      final startTime = args['startTime'] as String;
      final endTime = args['endTime'] as String;

      final start = DateTime.parse('${date}T$startTime:00');
      final end = DateTime.parse('${date}T$endTime:00');

      final event = calendar.Event(
        summary: args['title'] as String,
        start: calendar.EventDateTime(dateTime: start),
        end: calendar.EventDateTime(dateTime: end),
      );

      final created = await api.events.insert(event, 'primary');

      return {
        'status': 'created',
        'eventId': created.id,
        'summary': created.summary,
        'start': created.start?.dateTime?.toIso8601String(),
      };
    } catch (e) {
      GoogleAuthService.instance.invalidateClient();
      return {'error': 'Failed to create event: $e'};
    }
  }

  static Future<Map<String, dynamic>> _listEvents(
    Map<String, dynamic> args,
  ) async {
    try {
      final api = await GoogleAuthService.instance.getCalendarApi();

      final dateStr = args['date'] as String?;
      final targetDate =
          dateStr != null ? DateTime.parse(dateStr) : DateTime.now();

      final dayStart = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));

      final result = await api.events.list(
        'primary',
        timeMin: dayStart.toUtc(),
        timeMax: dayEnd.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      final events =
          (result.items ?? [])
              .map(
                (e) => {
                  'title': e.summary ?? '(no title)',
                  'start':
                      e.start?.dateTime?.toIso8601String() ??
                      e.start?.date?.toString(),
                  'end':
                      e.end?.dateTime?.toIso8601String() ??
                      e.end?.date?.toString(),
                },
              )
              .toList();

      return {
        'date': dayStart.toIso8601String().substring(0, 10),
        'count': events.length,
        'events': events,
      };
    } catch (e) {
      GoogleAuthService.instance.invalidateClient();
      return {'error': 'Failed to list events: $e'};
    }
  }

  static Future<Map<String, dynamic>> _readLatestEmail() async {
    try {
      final api = await GoogleAuthService.instance.getGmailApi();

      final list = await api.users.messages.list(
        'me',
        maxResults: 1,
        labelIds: ['INBOX'],
      );

      if (list.messages == null || list.messages!.isEmpty) {
        return {'status': 'empty', 'message': 'No emails found.'};
      }

      final messageId = list.messages!.first.id!;
      final message = await api.users.messages.get(
        'me',
        messageId,
        format: 'metadata',
        metadataHeaders: ['Subject', 'From'],
      );

      String? getHeader(String name) {
        final headers = message.payload?.headers ?? [];
        for (final h in headers) {
          if (h.name == name) return h.value;
        }
        return null;
      }

      return {
        'from': getHeader('From') ?? 'Unknown sender',
        'subject': getHeader('Subject') ?? '(no subject)',
        'snippet': message.snippet ?? '',
      };
    } catch (e) {
      GoogleAuthService.instance.invalidateClient();
      return {'error': 'Failed to read latest email: $e'};
    }
  }
}
