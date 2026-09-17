import 'package:flutter/material.dart';
import 'tool_handlers.dart';

class TestCalendarPage extends StatefulWidget {
  const TestCalendarPage({super.key});

  @override
  State<TestCalendarPage> createState() => _TestCalendarPageState();
}

class _TestCalendarPageState extends State<TestCalendarPage> {
  String _apiResult = 'Tap the button to test the Calendar API';
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();

  Future<void> _runTest() async {
    setState(() {
      _isLoading = true;
      _apiResult =
          'Fetching events for ${_selectedDate.toString().substring(0, 10)}...';
    });

    try {
      // 1. Create the dummy arguments map that the LLM would normally generate
      final dummyArgs = {'date': _selectedDate.toIso8601String()};

      // 2. Call your custom ToolHandler directly
      final result = await ToolHandlers.listEvents(dummyArgs);

      // 3. Format the map nicely to display on screen
      setState(() {
        _apiResult = _formatJson(result);
      });
    } catch (e) {
      setState(() {
        _apiResult = '❌ ERROR:\n$e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Quick helper to make the Map look pretty on screen
  String _formatJson(Map<String, dynamic> data) {
    if (data.containsKey('error')) return '❌ API Error: ${data['error']}';

    final buffer = StringBuffer();
    buffer.writeln('✅ SUCCESS! Found ${data['count']} events.\n');
    buffer.writeln('Date: ${data['date']}');
    buffer.writeln('----------------------');

    final events = data['events'] as List<dynamic>?;
    if (events != null && events.isNotEmpty) {
      for (var i = 0; i < events.length; i++) {
        final event = events[i] as Map<String, dynamic>;
        buffer.writeln('${i + 1}. ${event['title']}');
        buffer.writeln('   Start: ${event['start']}');
        buffer.writeln('   End:   ${event['end']}');
        buffer.writeln();
      }
    } else {
      buffer.writeln('No events scheduled for this day.');
    }

    return buffer.toString();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('API Sandbox: Calendar'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Testing Date: ${_selectedDate.toString().substring(0, 10)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('Change'),
                  onPressed: _isLoading ? null : _pickDate,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon:
                  _isLoading
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.play_arrow),
              label: Text(_isLoading ? 'Fetching...' : 'Run listEvents()'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isLoading ? null : _runTest,
            ),
            const SizedBox(height: 24),
            const Text(
              'Raw API Output:',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    _apiResult,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
