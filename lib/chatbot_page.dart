import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:gdg_edge_ai/tool_handlers.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

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
    required this.chat,
    required this.visionChat,
    required this.tts,
  });

  final InferenceChat chat;
  final InferenceChat visionChat;
  final FlutterTts tts;

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();

  String? _pendingImagePath;
  bool _isBotTyping = false;

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
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

  String _humanizeToolResult(Map<String, dynamic> result) {
    if (result['error'] != null) return 'I could not complete that request.';
    if (result['events'] is List) {
      final events = result['events'] as List;
      if (events.isEmpty) return 'You have no events on that date.';
      final descriptions = events
          .map((event) {
            final item = event as Map<String, dynamic>;
            return '${item['title']} at ${item['start'] ?? 'an unspecified time'}';
          })
          .join('; ');
      return 'Your events are: $descriptions.';
    }
    if (result['status'] == 'empty') return result['message'] as String;
    if (result['status'] == 'created') {
      return 'I created the calendar event "${result['summary']}".';
    }
    if (result['subject'] != null) {
      return 'Your latest email is from ${result['from']}, with subject '
          '"${result['subject']}". ${result['snippet']}';
    }
    return 'The request completed successfully.';
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    final imagePath = _pendingImagePath;

    if (text.isEmpty && imagePath == null) return;
    if (_isBotTyping) return;

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

    // Placeholder bot message that gets filled in as tokens stream in.
    var botMessage = ChatMessage(isUser: false, text: '');
    setState(() => _messages.add(botMessage));

    try {
      final imageBytes =
          imagePath == null ? null : await File(imagePath).readAsBytes();

      debugPrint('Image path: $imagePath');
      debugPrint('Image bytes: ${imageBytes?.length ?? 0}');

      final message =
          imageBytes == null
              ? Message.text(text: text, isUser: true)
              : Message.withImage(
                text:
                    text.isEmpty
                        ? 'Describe the attached image. Name the main objects.'
                        : text,
                imageBytes: imageBytes,
                isUser: true,
              );

      // final message =
      //     imagePath != null
      //         ? Message.withImage(
      //           text: text.isEmpty ? 'Describe this image.' : text,
      //           imageBytes: await File(imagePath).readAsBytes(),
      //           isUser: true,
      //         )
      //         : Message.text(text: text, isUser: true);

      final activeChat = imageBytes == null ? widget.chat : widget.visionChat;
      await activeChat.addQueryChunk(message);

      Map<String, dynamic>? lastToolResult;
      var toolWasCalled = false;
      final stream =
          imageBytes == null
              ? widget.chat.generateChatResponseWithTools(
                onToolCall: (call) async {
                  toolWasCalled = true;
                  final result = await ToolHandlers.handle(call);
                  lastToolResult = result;
                  return result;
                },
                maxToolTurns: 8,
              )
              : widget.visionChat.generateChatResponseAsync();

      // await for (final response in stream) {
      //   if (response is TextResponse) {
      //     setState(() {
      //       botMessage.text = (botMessage.text ?? '') + response.token;
      //     });
      //     _scrollToBottom();
      //   }
      //   // Other ModelResponse variants (thinking tokens, tool-call events)
      //   // can be handled here too if you want to surface "using a tool..."
      //   // status in the UI.
      // }
      await for (final response in stream) {
        if (response is TextResponse) {
          final token = response.token;

          // Safety net: never surface raw tool-call syntax to the user,
          // even if a future/older SDK version fails to parse it.
          final looksLikeToolCallLeak =
              token.contains('<|tool_call') || token.contains('<tool_call|>');
          if (looksLikeToolCallLeak) {
            debugPrint('Suppressed raw tool-call token leak: $token');
            continue;
          }

          setState(() {
            botMessage.text = (botMessage.text ?? '') + token;
          });
          _scrollToBottom();
          widget.tts.speak(botMessage.text?.trim() ?? '');
        } else if (response is FunctionCallResponse) {
          debugPrint('Tool call: ${response.name}(${response.args})');
          setState(() {
            botMessage.text = 'Using ${response.name}...';
          });
        }
      }

      final visibleText = botMessage.text?.trim() ?? '';
      if (imageBytes == null &&
          lastToolResult != null &&
          (visibleText.isEmpty ||
              toolWasCalled && visibleText.startsWith('Using '))) {
        setState(() {
          botMessage.text = _humanizeToolResult(lastToolResult!);
        });
      } else if (imageBytes == null && visibleText.startsWith('{')) {
        try {
          final decoded = jsonDecode(visibleText);
          if (decoded is Map<String, dynamic>) {
            setState(() => botMessage.text = _humanizeToolResult(decoded));
          }
        } on FormatException {
          // Leave ordinary model text unchanged.
        }
      }
    } catch (e) {
      setState(() {
        botMessage.text = 'Something went wrong: $e';
      });
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
              Text(message.text!, style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chatbot')),
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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.image_outlined),
                    onPressed: _pickImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  IconButton(
                    icon:
                        _isBotTyping
                            ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                            : const Icon(Icons.send),
                    onPressed: _isBotTyping ? null : _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
