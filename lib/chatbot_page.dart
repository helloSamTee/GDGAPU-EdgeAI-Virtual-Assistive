import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

// A single message in the chat, from either the user or the bot.
// Can carry text, an image, or both.
class ChatMessage {
  ChatMessage({required this.isUser, this.text, this.imagePath});

  final bool isUser;
  final String? text;
  final String? imagePath;
}

// A basic chatbot screen: user can type text and/or attach an image,
// send it, and receive a dummy bot response.
class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

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

  // Placeholder for a real chatbot backend call. Currently just waits
  // briefly and returns a canned response.
  Future<String> _getDummyBotResponse(String? text, String? imagePath) async {
    await Future.delayed(const Duration(milliseconds: 800));

    if (imagePath != null && text != null && text.isNotEmpty) {
      return "Thanks for the image and message! This is a dummy response — "
          "real analysis isn't wired up yet.";
    } else if (imagePath != null) {
      return "Nice photo! This is a placeholder response for image-only "
          "messages.";
    } else {
      return "This is a dummy response to: \"$text\"";
    }
  }

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    final imagePath = _pendingImagePath;

    if (text.isEmpty && imagePath == null) return;

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

    final responseText = await _getDummyBotResponse(
      text.isEmpty ? null : text,
      imagePath,
    );

    if (!mounted) return;

    setState(() {
      _isBotTyping = false;
      _messages.add(ChatMessage(isUser: false, text: responseText));
    });
    _scrollToBottom();
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
                    icon: const Icon(Icons.send),
                    onPressed: _sendMessage,
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
