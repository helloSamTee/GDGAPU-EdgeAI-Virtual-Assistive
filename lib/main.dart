import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import 'camera_page.dart';
import 'chatbot_page.dart';

Future<void> main() async {
  // Ensure that plugin services are initialized so that `availableCameras()`
  // can be called before `runApp()`
  WidgetsFlutterBinding.ensureInitialized();

  // Obtain a list of the available cameras on the device.
  final cameras = await availableCameras();

  // Get a specific camera from the list of available cameras.
  final firstCamera = cameras.isNotEmpty ? cameras.first : null;

  runApp(MyApp(camera: firstCamera));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.camera});

  final CameraDescription? camera;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flood Report Demo',
      theme: ThemeData.dark(),
      home: HomeScreen(camera: camera),
    );
  }
}

// A simple landing page that lets the user pick between the two dummy
// pages: the camera capture page and the chatbot page.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.camera});

  final CameraDescription? camera;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Demo Home')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Open Camera Page'),
              onPressed:
                  camera == null
                      ? null
                      : () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => CameraPage(camera: camera!),
                          ),
                        );
                      },
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Open Chatbot Page'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const ChatbotPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
