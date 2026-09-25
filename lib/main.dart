import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:gdg_edge_ai/test_list_events.dart';
import 'package:gdg_edge_ai/tool_handlers.dart';
import 'package:object_detection/object_detection.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'camera_page.dart';
import 'chatbot_page.dart';
import 'google_auth_service.dart';

const String _modelUrl =
    'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/'
    'resolve/main/gemma-4-E2B-it.litertlm';

const _localSkillNames = [
  'list-events',
  'create-calendar-event',
  'read-latest-email',
  // 'calculate-hash',
  // 'interactive-map',
  'kitchen-adventure',
  // 'mood-tracker',
  // 'qr-code',
  // 'query-wikipedia',
  // 'send-email',
  // 'text-spinner',
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  // initialize() just registers the plugin/engine — it does not download or
  // load anything, so it's safe (and fast) to await before runApp.
  final hfToken = dotenv.env['HUGGINGFACE_TOKEN'] ?? '';
  await FlutterGemma.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
    huggingFaceToken: hfToken.isNotEmpty ? hfToken : null,
  );

  // Everything heavy (camera enumeration, model download/load, object
  // detector init, Google auth) now happens INSIDE the app, after the first
  // frame renders, with progress shown on screen instead of blocking here.
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vision-Assistive AI Application',
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}

enum _InitStage { auth, camera, modelDownload, modelLoad, detector, ready }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  _InitStage _stage = _InitStage.camera;
  double? _downloadProgress; // 0.0–1.0, null while not downloading
  String? _initError;

  CameraDescription? _camera;
  ObjectDetector? _detector;
  FlutterTts? _tts;
  dynamic _model;
  AgentSession? _agentSession;

  bool _isSigningIn = false;
  bool _isGoogleAuthenticated = false;
  String? _authMessage;
  int _selectedIndex = 0;

  // This list stores the screens for each tab
  List<Widget> get _screens => [
    CameraPage(
      camera: _camera!,
      detector: _detector!,
      agent: _agentSession!,
      tts: _tts!,
    ),
    ChatbotPage(agent: _agentSession!, tts: _tts!, onClearChat: _resetChat),
  ];

  @override
  void initState() {
    super.initState();
    unawaited(_startInitialization());
  }

  Future<void> _startInitialization() async {
    if (mounted) {
      setState(() => _stage = _InitStage.auth);
    }
    await _ensureGoogleAuth();
    await _initEverything();
  }

  Future<void> _initEverything() async {
    try {
      setState(() => _stage = _InitStage.camera);
      final cameras = await availableCameras();
      _camera = cameras.isNotEmpty ? cameras.first : null;

      setState(() {
        _stage = _InitStage.modelDownload;
        _downloadProgress = 0;
      });

      final hfToken = dotenv.env['HUGGINGFACE_TOKEN'];

      // ADDITION: Implement a retry loop to survive WorkManager interruptions
      bool modelDownloaded = false;
      int retryCount = 0;
      const maxRetries = 5;

      // Turn on the wakelock to keep the screen on
      await WakelockPlus.enable();

      try {
        while (!modelDownloaded && retryCount < maxRetries) {
          try {
            // install() is idempotent: it skips an existing download and restores
            // the active model identity needed by getActiveModel().
            await FlutterGemma.installModel(
                  modelType: ModelType.gemma4,
                  fileType: ModelFileType.litertlm,
                )
                .fromNetwork(
                  _modelUrl,
                  token: hfToken?.isNotEmpty == true ? hfToken : null,
                )
                .withProgress((progress) {
                  if (mounted) {
                    setState(() => _downloadProgress = progress / 100);
                  }
                })
                .install();

            modelDownloaded = true; // Success! Break the loop.
          } catch (e) {
            final errorStr = e.toString().toLowerCase();
            if (errorStr.contains('canceled') ||
                errorStr.contains('cancelled')) {
              retryCount++;
              print(
                'Download interrupted by OS. Resuming (Attempt $retryCount of $maxRetries)...',
              );
              // Give the OS WorkManager a brief moment to reschedule before re-attaching
              await Future.delayed(const Duration(seconds: 2));
            } else {
              // If it's a different error (like 401 Unauthorized), throw it normally
              rethrow;
            }
          }
        }

        if (!modelDownloaded) {
          throw Exception(
            'Failed to download model after $maxRetries attempts.',
          );
        }
      } finally {
        // Turn off the wakelock after the download attempt
        await WakelockPlus.disable();
      }

      setState(() => _stage = _InitStage.modelLoad);

      _model = await FlutterGemma.getActiveModel(
        maxTokens: 4096,
        // The device's OpenCL LiteRT accelerator crashes while compiling this
        // model. CPU is slower, but keeps model startup inside Dart's error
        // handling instead of terminating the process in native code.
        preferredBackend: PreferredBackend.cpu,
        // The vision encoder has its own backend; keep it on CPU too.
        preferredVisionBackend: PreferredBackend.cpu,
        supportImage: true,
        maxNumImages: 1,
      );

      // final source = AssetSkillSource();
      // final loadedSkills = await source.load();

      await _createAgentSession();

      setState(() => _stage = _InitStage.detector);
      _detector = await ObjectDetector.create();

      setState(() => _stage = _InitStage.detector);
      _detector = await ObjectDetector.create();

      _tts = FlutterTts();
      await _tts!.setLanguage('en-US');
      await _tts!.setSpeechRate(0.5);
      await _tts!.setPitch(1.0);

      if (!mounted) return;
      setState(() => _stage = _InitStage.ready);
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = 'Setup failed: $e');
    }
  }

  Future<void> _ensureGoogleAuth() async {
    setState(() {
      _isSigningIn = true;
      _authMessage = null;
    });

    try {
      await GoogleAuthService.instance.getAuthenticatedClient();
      if (!mounted) return;
      final account = GoogleAuthService.instance.account;
      setState(() {
        _isGoogleAuthenticated = true;
        _isSigningIn = false;
        _authMessage =
            'Signed in as ${account?.displayName ?? account?.email ?? 'Google account'}'
            '${account?.displayName != null ? '\n${account!.email}' : ''}';
      });
      _agentSession?.registry.select('list-events');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isGoogleAuthenticated = false;
        _isSigningIn = false;
        _authMessage = 'Google sign-in failed: $error';
      });
    }
  }

  Future<void> _switchGoogleAccount() async {
    if (_isSigningIn) return;

    try {
      await GoogleAuthService.instance.signOut();
      if (!mounted) return;
      setState(() {
        _isGoogleAuthenticated = false;
        _authMessage = null;
      });
      await _ensureGoogleAuth();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isGoogleAuthenticated = false;
        _authMessage = 'Google sign-out failed: $error';
      });
    }
  }

  Future<List<Skill>> _loadLocalSkills() async {
    final skills = <Skill>[];
    for (final name in _localSkillNames) {
      final text = await rootBundle.loadString('assets/skills/$name/SKILL.md');
      skills.add(parseSkillMd(text));
    }
    return skills;
  }

  Future<void> _createAgentSession() async {
    final source = AssetSkillSource();
    // final bundled_starter_skills = await source.load();
    // final registry = SkillRegistry()..addAll(bundled_starter_skills, selected: true);

    final loadedSkills = await _loadLocalSkills();
    final registry = SkillRegistry();

    for (final skill in loadedSkills) {
      if (skill.name == 'list-events') {
        registry.add(skill, selected: _isGoogleAuthenticated);
      } else {
        registry.add(skill, selected: true);
      }
    }

    _agentSession = await AgentSession.fromModel(
      _model,
      registry: registry,
      supportImage: true,
      executors: [
        TextSkillExecutor(),
        JsSkillExecutor(sourceFor: source.jsSkillSourceFor),
        NativeIntentExecutor(),
        McpSkillExecutor(
          // clients: [
          //   McpClient(
          //     config: McpServerConfig(url: 'http://127.0.0.1:8765/mcp'),
          //   ),
          // ],
        ),
        LocalDartSkillExecutor(),
      ],
    );

    if (_isGoogleAuthenticated) {
      _agentSession!.registry.select('list-events');
    }
  }

  // Called when the user clicks the "Trash" icon
  Future<void> _resetChat() async {
    // Show a quick loading state if you want, or just wait for it to recreate
    await _createAgentSession();
    setState(() {}); // Rebuild the UI so ChatbotPage gets the fresh agent
  }

  String _stageLabel() {
    switch (_stage) {
      case _InitStage.auth:
        return _isSigningIn
            ? 'Signing in with Google...'
            : 'Preparing Google services...';
      case _InitStage.camera:
        return 'Finding cameras...';
      case _InitStage.modelDownload:
        return _downloadProgress != null
            ? 'Downloading model: ${(_downloadProgress! * 100).toStringAsFixed(0)}%'
            : 'Preparing model download...';
      case _InitStage.modelLoad:
        return 'Loading model into memory...';
      case _InitStage.detector:
        return 'Starting object detector...';
      case _InitStage.ready:
        return 'Ready';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _stage == _InitStage.ready;

    return Scaffold(
      appBar: AppBar(title: const Text('Edge AI Vision Assistant')),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex, // Highlight the selected tab
        onTap: (index) {
          setState(() {
            _selectedIndex = index; // Update selected index
          });
        },
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.camera), label: 'Camera'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Chat'),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_initError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _initError!,
                    style: const TextStyle(color: Colors.redAccent),
                    textAlign: TextAlign.center,
                  ),
                ),
              if (!isReady && _initError == null) ...[
                Text(_stageLabel(), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                if (_stage == _InitStage.modelDownload)
                  SizedBox(
                    width: 240,
                    child: LinearProgressIndicator(value: _downloadProgress),
                  )
                else
                  const CircularProgressIndicator(),
                const SizedBox(height: 24),
              ],
              if (_authMessage != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _authMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          _isGoogleAuthenticated
                              ? Colors.greenAccent
                              : Colors.orangeAccent,
                    ),
                  ),
                ),
              if (_isSigningIn)
                const Padding(
                  padding: EdgeInsets.only(bottom: 16),
                  child: CircularProgressIndicator(),
                ),
              if (!_isGoogleAuthenticated)
                ElevatedButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('Sign in with Google'),
                  onPressed: _isSigningIn ? null : _ensureGoogleAuth,
                ),
              if (_isGoogleAuthenticated)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.switch_account),
                    label: const Text('Switch Google account'),
                    onPressed: _isSigningIn ? null : _switchGoogleAccount,
                  ),
                ),
              // if (_isGoogleAuthenticated)
              //   Padding(
              //     padding: const EdgeInsets.only(top: 16.0),
              //     child: OutlinedButton.icon(
              //       icon: const Icon(Icons.bug_report, color: Colors.orange),
              //       label: const Text('Open Calendar Sandbox'),
              //       onPressed: () {
              //         Navigator.of(context).push(
              //           MaterialPageRoute(
              //             builder: (context) => const TestCalendarPage(),
              //           ),
              //         );
              //       },
              //     ),
              //   ),
              if (isReady &&
                  _camera != null &&
                  _agentSession != null &&
                  _detector != null)
                Expanded(child: _screens[_selectedIndex]),
            ],
          ),
        ),
      ),
    );
  }
}
