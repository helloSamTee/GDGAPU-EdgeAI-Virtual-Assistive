import 'package:flutter_gemma/flutter_gemma.dart';

import 'google_auth_service.dart';

// Dispatches a FunctionCallResponse from the model to the matching Dart
// implementation, and returns a plain Map the model can read back as the
// tool's result.
class ToolHandlers {
  static Future<Map<String, dynamic>> handle(FunctionCallResponse call) {
    switch (call.name) {
      // case 'create_calendar_event':
      //   return _createCalendarEvent(call.args);
      case 'list-events':
        return listEvents(call.args);
      // case 'read_latest_email':
      //   return _readLatestEmail();
      default:
        return Future.value({'error': 'Unknown tool: ${call.name}'});
    }
  }

  // static Future<Map<String, dynamic>> _createCalendarEvent(
  //   Map<String, dynamic> args,
  // ) async {
  //   try {
  //     final api = await GoogleAuthService.instance.getCalendarApi();

  //     final date = args['date'] as String;
  //     final startTime = args['startTime'] as String;
  //     final endTime = args['endTime'] as String;

  //     final start = DateTime.parse('${date}T$startTime:00');
  //     final end = DateTime.parse('${date}T$endTime:00');

  //     final event = calendar.Event(
  //       summary: args['title'] as String,
  //       start: calendar.EventDateTime(dateTime: start),
  //       end: calendar.EventDateTime(dateTime: end),
  //     );

  //     final created = await api.events.insert(event, 'primary');

  //     return {
  //       'status': 'created',
  //       'eventId': created.id,
  //       'summary': created.summary,
  //       'start': created.start?.dateTime?.toIso8601String(),
  //     };
  //   } catch (e) {
  //     GoogleAuthService.instance.invalidateClient();
  //     return {'error': 'Failed to create event: $e'};
  //   }
  // }

  static Future<Map<String, dynamic>> listEvents(
    Map<String, dynamic> args,
  ) async {
    try {
      final api = await GoogleAuthService.instance.getCalendarApi();

      // 1. Safely handle whatever the LLM throws at the date parameter
      final dateStr = args['date'] as String?;
      DateTime targetDate = DateTime.now(); // Default to today

      if (dateStr != null && dateStr.isNotEmpty) {
        try {
          targetDate = DateTime.parse(dateStr);
        } catch (e) {
          print(
            '⚠️ LLM sent invalid date format: "$dateStr". Falling back to today.',
          );
          // If the LLM sends "today" or "tomorrow", we just default to DateTime.now()
        }
      }

      final dayStart = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));

      print('📅 Fetching events for: $dayStart');

      final result = await api.events.list(
        'primary',
        timeMin: dayStart.toUtc(),
        timeMax: dayEnd.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
        maxResults: 5,
      );

      final events =
          (result.items ?? []).map((e) {
            // --- FIX 2: Compress the timestamp strings ---
            // Convert "2026-09-17T10:00:00.000" to just "10:00"
            String formatTime(String? isoString) {
              if (isoString == null) return '';
              try {
                final dt = DateTime.parse(isoString).toLocal();
                return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              } catch (_) {
                return isoString.substring(0, 10); // Fallback to just the date
              }
            }

            return {
              't':
                  e.summary ??
                  '(no title)', // 't' instead of 'title' saves bytes
              's': formatTime(
                e.start?.dateTime?.toIso8601String() ??
                    e.start?.date?.toString(),
              ), // 's' instead of 'start'
              'e': formatTime(
                e.end?.dateTime?.toIso8601String() ?? e.end?.date?.toString(),
              ), // 'e' instead of 'end'
            };
          }).toList();

      return {
        'date': dayStart.toIso8601String().substring(0, 10),
        'count': events.length,
        'events': events,
      };
    } catch (e) {
      print('❌ Calendar API Error: $e');
      // 2. Only invalidate the client if the token is ACTUALLY expired (401 Unauthorized)
      if (e.toString().contains('401') || e.toString().contains('403')) {
        GoogleAuthService.instance.invalidateClient();
      }
      return {'error': 'Failed to list events: $e'};
    }
  }

  // static Future<Map<String, dynamic>> _readLatestEmail() async {
  //   try {
  //     final api = await GoogleAuthService.instance.getGmailApi();

  //     final list = await api.users.messages.list(
  //       'me',
  //       maxResults: 1,
  //       labelIds: ['INBOX'],
  //     );

  //     if (list.messages == null || list.messages!.isEmpty) {
  //       return {'status': 'empty', 'message': 'No emails found.'};
  //     }

  //     final messageId = list.messages!.first.id!;
  //     final message = await api.users.messages.get(
  //       'me',
  //       messageId,
  //       format: 'metadata',
  //       metadataHeaders: ['Subject', 'From'],
  //     );

  //     String? getHeader(String name) {
  //       final headers = message.payload?.headers ?? [];
  //       for (final h in headers) {
  //         if (h.name == name) return h.value;
  //       }
  //       return null;
  //     }

  //     return {
  //       'from': getHeader('From') ?? 'Unknown sender',
  //       'subject': getHeader('Subject') ?? '(no subject)',
  //       'snippet': message.snippet ?? '',
  //     };
  //   } catch (e) {
  //     GoogleAuthService.instance.invalidateClient();
  //     return {'error': 'Failed to read latest email: $e'};
  //   }
  // }
}
