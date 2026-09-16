import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';

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
  const ChatbotPage({super.key, required this.agent, required this.tts});

  final AgentSession agent;
  final FlutterTts tts;

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final List<ChatMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Speech to Text variables
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  bool _isListening = false;

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
  void _startListening() async {
    await _speechToText.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            // Update the text field with the recognized words
            _textController.text = result.recognizedWords;
          });
        }
      },
    );
    setState(() => _isListening = true);
  }

  // Stop listening
  void _stopListening() async {
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

  Future<void> _sendMessage() async {
    final text = _textController.text.trim();
    final imagePath = _pendingImagePath;

    if (text.isEmpty && imagePath == null) return;
    if (_isBotTyping) return;

    // Stop listening if the user manually hits send while talking
    if (_isListening) {
      _stopListening();
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
              : text;

      await for (final event in widget.agent.ask(
        prompt,
        imageBytes: imageBytes,
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
        }
      }

      // 2. Speak the COMPLETE message only after the stream is fully finished
      if (botMessage.text != null && botMessage.text!.isNotEmpty) {
        await widget.tts.speak(botMessage.text!.trim());
      }
    } catch (e) {
      setState(() => botMessage.text = 'Something went wrong: $e');
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
                  if (_speechEnabled)
                    IconButton(
                      icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                      color: _isListening ? Colors.redAccent : null,
                      onPressed:
                          _isListening ? _stopListening : _startListening,
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
