import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

// A single message in the chat, from either the user or the bot.
// Can carry text, an image, or both.
class ChatMessage {
  ChatMessage({required this.isUser, this.text, this.imagePath});

  final bool isUser;
  String? text;
  final String? imagePath;
}

// A basic chatbot screen: user can type text and/or attach an image, and send it.
// Chat screen wired to an InferenceChat that was created in main.dart with AppTools, all passed as its tools.
// This page just drives the send/receive loop and lets ToolHandlers.handle execute whatever the model asks for.
class ChatbotPage extends StatefulWidget {
  const ChatbotPage({
    super.key,
    required this.agent,
    required this.tts,
    required this.onClearChat,
  });

  final AgentSession agent;
  final FlutterTts tts;
  final VoidCallback onClearChat;

  @override
  State<ChatbotPage> createState() => ChatbotPageState();
}

class ChatbotPageState extends State<ChatbotPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Speech to Text variables
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;

  bool get isListening => _isListening;

  final ImagePicker _imagePicker = ImagePicker();
  String? _pendingImagePath;
  bool _isBotTyping = false;

  @override
  void initState() {
    super.initState();
    _initSpeech(); // Initialize speech recognition
  }

  // Initialize the speech-to-text service
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
      onError: (errorNotification) {
        print('Speech recognition error: $errorNotification');
        if (mounted) setState(() => _isListening = false);
      },
    );
    if (mounted) setState(() {});
  }

  // Start listening to the microphone
  Future<void> startVoiceInput() async {
    await _speechToText.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            // Update the text field with the recognized words
            _textController.text += result.recognizedWords;
          });
        }
      },
    );
    setState(() => _isListening = true);
  }

  // Stop listening
  Future<void> stopVoiceInput() async {
    await _speechToText.stop();
    setState(() => _isListening = false);
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _speechToText.cancel();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
    );
    if (picked != null) {
      setState(() => _pendingImagePath = picked.path);
    }
  }

  void _clearPendingImage() {
    setState(() => _pendingImagePath = null);
  }

  void _handleClearChat() {
    // Clear the UI messages
    setState(() {
      _messages.clear();
      _textController.clear();
      _pendingImagePath = null;
    });
    // Tell HomeScreen to recreate the AgentSession (clearing the LLM's memory)
    widget.onClearChat();
  }

  String buildDateContext() {
    final now = DateTime.now();
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final iso = now.toIso8601String().substring(0, 10);
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final offset = now.timeZoneOffset;
    final tz =
        '${offset.isNegative ? '-' : '+'}'
        '${offset.inHours.abs().toString().padLeft(2, '0')}:'
        '${(offset.inMinutes.abs() % 60).toString().padLeft(2, '0')}';
    return 'Current date: ${days[now.weekday - 1]} $iso, time $hh:$mm (UTC$tz).';
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    final imagePath = _pendingImagePath;

    if (text.isEmpty && imagePath == null) return;
    if (_isBotTyping) return;

    // Stop listening if the user manually hits send while talking
    if (_isListening) {
      stopVoiceInput();
    }

    setState(() {
      _messages.add(
        ChatMessage(
          isUser: true,
          text: text.isEmpty ? null : text,
          imagePath: imagePath,
        ),
      );
      _isBotTyping = true;
    });

    _textController.clear();
    _clearPendingImage();
    _scrollToBottom();

    var botMessage = ChatMessage(isUser: false, text: '');
    setState(() => _messages.add(botMessage));

    try {
      final imageBytes =
          imagePath == null ? null : await File(imagePath).readAsBytes();

      // ask() needs non-empty text even for an image-only send.
      final prompt =
          text.isEmpty
              ? 'Describe the attached image. Name the main objects.'
              : '${buildDateContext()}\n\n$text';

      await for (final event in widget.agent.ask(
        // == AGENT PLACEHOLDER ==
      )) {
        if (event is TextChunkEvent) {
          setState(() {
            botMessage.text = (botMessage.text ?? '') + event.text;
          });
          _scrollToBottom();
        }
        // You can optionally handle other events here, like ToolCallEvent
        else if (event is ToolCallEvent) {
          print('Bot is calling tool: ${event.toolName}');
          setState(() {
            botMessage.text =
                '${botMessage.text ?? ''}\n[Checking ${event.toolName}...]\n';
          });
          _scrollToBottom();
        }
      }

      // 2. Speak the COMPLETE message only after the stream is fully finished
      if (botMessage.text != null && botMessage.text!.isNotEmpty) {
        // == TTS PLACEHOLDER ==
      }
    } catch (e) {
      final errorStr = e.toString();
      setState(() {
        // Intercept the token limit error and give a friendly message
        if (errorStr.contains('FAILED_PRECONDITION') ||
            errorStr.contains('Prefill input length')) {
          botMessage.text =
              'My memory is full! Please tap the trash icon in the top right to start a new conversation.';
        } else {
          botMessage.text = 'Something went wrong: $e';
        }
      });
      print('Chat Error: $e');
    } finally {
      setState(() => _isBotTyping = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final alignment =
        message.isUser ? Alignment.centerRight : Alignment.centerLeft;
    final color = message.isUser ? Colors.blueAccent : Colors.grey[800];

    return Align(
      alignment: alignment,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(message.imagePath!),
                  width: 180,
                  fit: BoxFit.cover,
                ),
              ),
            if (message.imagePath != null && message.text != null)
              const SizedBox(height: 6),
            if (message.text != null)
              GptMarkdown(
                message.text!,
                style: const TextStyle(color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chatbot'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Clear Chat',
            onPressed: _handleClearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _messages.length + (_isBotTyping ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == _messages.length && _isBotTyping) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        'Bot is typing...',
                        style: TextStyle(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  );
                }
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),
          if (_pendingImagePath != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(_pendingImagePath!),
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Image attached')),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _clearPendingImage,
                  ),
                ],
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                  child: Column(
                    children: [
                      TextField(
                        controller: _textController,
                        minLines: 1,
                        maxLines: 5,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'Write a message...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Attach image',
                            icon: const Icon(Icons.image_outlined),
                            onPressed: _pickImage,
                          ),
                          if (_speechEnabled)
                            IconButton(
                              tooltip: 'Voice input',
                              icon: Icon(
                                _isListening ? Icons.mic : Icons.mic_none,
                              ),
                              color: _isListening ? Colors.redAccent : null,
                              onPressed:
                                  _isListening
                                      ? stopVoiceInput
                                      : startVoiceInput,
                            ),
                          const Spacer(),
                          IconButton.filled(
                            tooltip: 'Send message',
                            icon:
                                _isBotTyping
                                    ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : const Icon(Icons.arrow_upward),
                            onPressed: _isBotTyping ? null : _sendMessage,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
