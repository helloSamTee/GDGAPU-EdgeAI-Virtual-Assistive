import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

// A screen that allows users to take a picture using a given camera,
// and then runs a dummy "action" against the captured image
// (e.g. a stand-in for an upload / classification call).
class CameraPage extends StatefulWidget {
  const CameraPage({super.key, required this.camera});

  final CameraDescription camera;

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

  // Placeholder for whatever real action should happen after capture
  // (e.g. uploading the photo, running it through a model, attaching it
  // to a flood report). Currently just simulates a short delay and
  // returns a dummy result string.
  Future<String> _performActionOnImage(String imagePath) async {
    await Future.delayed(const Duration(seconds: 1));
    return 'Dummy action complete for image at $imagePath';
  }

  Future<void> _onCapturePressed() async {
    if (_isProcessing) return;

    try {
      await _initializeControllerFuture;

      setState(() => _isProcessing = true);

      final image = await _controller.takePicture();
      final resultMessage = await _performActionOnImage(image.path);

      if (!mounted) return;

      setState(() => _isProcessing = false);

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder:
              (context) => DisplayPictureScreen(
                imagePath: image.path,
                actionResult: resultMessage,
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
  });

  final String imagePath;
  final String actionResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Display the Picture')),
      body: Column(
        children: [
          Expanded(child: Image.file(File(imagePath))),
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
