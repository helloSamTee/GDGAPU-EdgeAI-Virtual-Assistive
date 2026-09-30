import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;

import 'google_auth_service.dart';

// Dispatches a FunctionCallResponse from the model to the matching Dart
// implementation, and returns a plain Map the model can read back as the
// tool's result.
class ToolHandlers {
  static Future<Map<String, dynamic>> handle(FunctionCallResponse call) {
    switch (call.name) {
      case 'create-calendar-event':
        return createCalendarEvent(call.args);
      case 'list-events':
        return listEvents(call.args);
      case 'read-latest-email':
        return readLatestEmail();
      default:
        return Future.value({'error': 'Unknown tool: ${call.name}'});
    }
  }

  static DateTime resolveDate(String? raw) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day).toUtc();
    final s = (raw ?? '').trim().toLowerCase();

    if (s.isEmpty || s == 'today') return today;
    if (s == 'tomorrow') return today.add(const Duration(days: 1));
    if (s == 'yesterday') return today.subtract(const Duration(days: 1));

    return DateTime.tryParse(s) ?? today;
  }

  static Future<Map<String, dynamic>> createCalendarEvent(
    Map<String, dynamic> args,
  ) async {
    try {
      final api = await GoogleAuthService.instance.getCalendarApi();

      // 1. Safely extract strings. If null, default to empty string.
      final title = (args['title'] ?? '(No Title)') as String;
      final dateDT = resolveDate((args['date'] ?? '') as String);
      final dateStr = dateDT.toIso8601String().substring(0, 10); // YYYY-MM-DD
      final startTimeStr = (args['startTime'] ?? '') as String;
      final endTimeStr = (args['endTime'] ?? '') as String;

      // 2. Validate that the LLM actually provided the required time fields
      if (dateStr.isEmpty || startTimeStr.isEmpty || endTimeStr.isEmpty) {
        return {
          'error':
              'Missing required fields. The LLM must provide date, startTime, and endTime.',
        };
      }

      DateTime start;
      DateTime end;

      // 3. Catch parsing errors in case the LLM formatting is weird (e.g., "10:00 AM" instead of "10:00")
      try {
        // Sanitize just in case it added seconds or whitespace
        final cleanStart = startTimeStr.trim().substring(0, 5);
        final cleanEnd = endTimeStr.trim().substring(0, 5);

        start = DateTime.parse('${dateStr.trim()}T$cleanStart:00');
        end = DateTime.parse('${dateStr.trim()}T$cleanEnd:00');
      } catch (e) {
        return {
          'error':
              'Invalid time format. LLM sent: date=$dateStr, start=$startTimeStr, end=$endTimeStr',
        };
      }

      final event = calendar.Event(
        summary: title,
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
      print('❌ Calendar API Error: $e');
      if (e.toString().contains('401') || e.toString().contains('403')) {
        GoogleAuthService.instance.invalidateClient();
      }
      return {'error': 'Failed to create event: $e'};
    }
  }

  static Future<Map<String, dynamic>> listEvents(
    Map<String, dynamic> args,
  ) async {
    try {
      final api = await GoogleAuthService.instance.getCalendarApi();

      final targetDate = resolveDate(args['date'] as String?);

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

  static Future<Map<String, dynamic>> readLatestEmail() async {
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

class LocalDartSkillExecutor extends SkillExecutor {
  @override
  String get name => 'local_dart_skill_executor';

  @override
  int get priority => 10;

  @override
  bool canExecute(String skillType) => true;

  @override
  bool canExecuteSkill(Skill skill) {
    // Tell the agent we can handle all three of these skills
    return [
      'list-events',
      'create-calendar-event',
      'read-latest-email',
    ].contains(skill.name);
  }

  @override
  Future<SkillResult> execute(
    Skill skill,
    String dataJson, {
    String? secret,
  }) async {
    print('⚡ Executing native Dart function for ${skill.name}!');
    try {
      // Safely decode args (readlatest--email will just pass an empty map)
      final args =
          dataJson.isEmpty
              ? <String, dynamic>{}
              : jsonDecode(dataJson) as Map<String, dynamic>;

      Map<String, dynamic> result;

      // Route the execution based on the skill name
      if (skill.name == 'list-events') {
        result = await ToolHandlers.listEvents(args);
      } else if (skill.name == 'create-calendar-event') {
        // You will need to change _createCalendarEvent from private to public in ToolHandlers!
        result = await ToolHandlers.createCalendarEvent(args);
      } else if (skill.name == 'read-latest-email') {
        // You will need to change _readLatestEmail from private to public in ToolHandlers!
        result = await ToolHandlers.readLatestEmail();
      } else {
        return ErrorResult('Skill not implemented.');
      }

      return TextResult(jsonEncode(result));
    } catch (e) {
      return ErrorResult('Error executing tool: $e');
    }
  }
}
