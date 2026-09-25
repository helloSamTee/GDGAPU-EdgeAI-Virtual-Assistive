import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:object_detection/object_detection.dart';

// A screen that allows users to take a picture using a given camera,
// and then runs a dummy "action" against the captured image
// (e.g. a stand-in for an upload / classification call).
class CameraPage extends StatefulWidget {
  const CameraPage({
    super.key,
    required this.camera,
    required this.detector,
    required this.agent,
    required this.tts,
  });

  final CameraDescription camera;
  final ObjectDetector detector;
  final AgentSession agent;
  final FlutterTts tts;

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;

  // Tracks whether the dummy action is currently "running" so we can
  // show a loading state on the capture button.
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _controller = CameraController(widget.camera, ResolutionPreset.medium);
    _initializeControllerFuture = _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDetectionSummary(List<DetectedObject> detections) {
    if (detections.isEmpty) {
      return 'No objects detected.';
    }

    final labels = <String>[];
    for (final obj in detections) {
      final label = obj.categoryName;
      final confidence = (obj.score * 100).toStringAsFixed(1);
      labels.add('$label ($confidence% confidence)');
    }

    return labels.join(', ');
  }

  Future<(String, String?, List<DetectedObject>)> _performActionOnImage(
    Future<Uint8List> imageBytes,
  ) async {
    final detectedBytes = await imageBytes;
    final detections; // == OBJECT DETECTION PLACEHOLDER ==

    final detectionSummary = _formatDetectionSummary(detections);
    debugPrint('Camera image bytes: ${detectedBytes.length}');

    final inferencePrompt =
        'I detected these objects in the image: $detectionSummary. '
        'Describe the scene briefly, mention any visible text, and explain '
        'what is most important to a visually impaired user in 3 to 5 sentences only.';

    String response = '';
    await for (final event in widget.agent.ask(
      // == INFERENCE PLACEHOLDER ==
    )) {
      if (event is TextChunkEvent) {
        response += event.text;
      }
      // You can optionally handle other events here, like ToolCallEvent
      else if (event is ToolCallEvent) {
        print('Bot is calling tool: ${event.toolName}');
      }
    }

    if (response.isNotEmpty) {
      debugPrint('Model Response: $response');
    } else {
      debugPrint('No response from model.');
    }

    final resultMessage =
        detections.isEmpty
            ? 'No objects detected.'
            : 'Detected objects: $detectionSummary.';

    return (resultMessage, response, detections);
  }

  Future<void> _onCapturePressed() async {
    if (_isProcessing) return;

    try {
      await _initializeControllerFuture;

      setState(() => _isProcessing = true);

      final image = await _controller.takePicture();
      final (
        resultMessage,
        ttsMessage,
        detections,
      ) = await _performActionOnImage(image.readAsBytes());

      if (!mounted) return;

      setState(() => _isProcessing = false);
      // == TTS PLACEHOLDER ==

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (context) => DisplayPictureScreen(
                imagePath: image.path,
                actionResult: resultMessage,
                ttsMessage: ttsMessage,
                detections: detections,
              ),
        ),
      );
    } catch (e) {
      // If an error occurs, log it and reset the loading state.
      debugPrint('Error capturing image: $e');
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Take a picture')),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            return CameraPreview(_controller);
          } else {
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _onCapturePressed,
        child:
            _isProcessing
                ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : const Icon(Icons.camera_alt),
      ),
    );
  }
}

// A widget that displays the picture taken by the user, along with the
// result of whatever dummy action was performed on it.
class DisplayPictureScreen extends StatelessWidget {
  const DisplayPictureScreen({
    super.key,
    required this.imagePath,
    required this.actionResult,
    required this.ttsMessage,
    required this.detections,
  });

  final String imagePath;
  final String actionResult;
  final String? ttsMessage;
  final List<DetectedObject> detections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final imageFile = File(imagePath);

                if (detections.isEmpty) {
                  return Center(
                    child: Image.file(imageFile, fit: BoxFit.contain),
                  );
                }

                final originalSize = detections.first.originalSize;
                final fitted = applyBoxFit(
                  BoxFit.contain,
                  originalSize,
                  Size(constraints.maxWidth, constraints.maxHeight),
                );
                final renderSize = fitted.destination;
                final imageRect = Alignment.center.inscribe(
                  renderSize,
                  Offset.zero &
                      Size(constraints.maxWidth, constraints.maxHeight),
                );

                return Stack(
                  children: [
                    Positioned.fromRect(
                      rect: imageRect,
                      child: Image.file(
                        imageFile,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      ),
                    ),
                    Positioned.fromRect(
                      rect: imageRect,
                      child: CustomPaint(
                        painter: DetectionsPainter(
                          detections: detections,
                          imageRectOnCanvas: Rect.fromLTWH(
                            0,
                            0,
                            imageRect.width,
                            imageRect.height,
                          ),
                          originalImageSize: originalSize,
                          showBoundingBoxes: true,
                          showLabels: true,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              actionResult,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
