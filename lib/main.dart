import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart'
    show EventChannel, HapticFeedback, rootBundle;
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_litertlm/flutter_gemma_litertlm.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:gdg_edge_ai/tool_handlers.dart';
import 'package:object_detection/object_detection.dart';
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'camera_page.dart';
import 'chatbot_page.dart';
import 'account_page.dart';
import 'google_auth_service.dart';

const String _modelUrl = ""; // == MODEL VARIANT PLACEHOLDER ==

const _localSkillNames = []; // == AGENTIC SKILLS PLACEHOLDER ==

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
  final _cameraPageKey = GlobalKey<CameraPageState>();
  final _chatbotPageKey = GlobalKey<ChatbotPageState>();
  StreamSubscription<dynamic>? _volumeSubscription;

  // This list stores the screens for each tab
  List<Widget> get _screens => [
    CameraPage(
      key: _cameraPageKey,
      camera: _camera!,
      detector: _detector!,
      agent: _agentSession!,
      tts: _tts!,
    ),
    ChatbotPage(
      key: _chatbotPageKey,
      agent: _agentSession!,
      tts: _tts!,
      onClearChat: _resetChat,
    ),
    AccountPage(
      account: GoogleAuthService.instance.account,
      isSigningIn: _isSigningIn,
      isAuthenticated: _isGoogleAuthenticated,
      message: _authMessage,
      onSignIn: _ensureGoogleAuth,
      onSignOut: _signOutGoogleAccount,
      onSwitchAccount: _switchGoogleAccount,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _listenForVolumeKeys();
    unawaited(_startInitialization());
  }

  void _listenForVolumeKeys() {
    if (defaultTargetPlatform != TargetPlatform.android) return;

    const channel = EventChannel('gdg_edge_ai/volume_keys');
    _volumeSubscription = channel.receiveBroadcastStream().listen((event) {
      if (event is! Map) return;
      final type = event['type'];
      if (type == 'switchTab') {
        _switchTabFromHardware();
      } else if (type == 'action') {
        _runActiveTabAction();
      }
    });
  }

  void _switchTabFromHardware() {
    if (!mounted) return;
    final nextIndex = (_selectedIndex + 1) % 3;
    HapticFeedback.heavyImpact();
    setState(() => _selectedIndex = nextIndex);
  }

  void _runActiveTabAction() {
    HapticFeedback.mediumImpact();
    switch (_selectedIndex) {
      case 0:
        _cameraPageKey.currentState?.captureAndDescribe();
      case 1:
        final chatbot = _chatbotPageKey.currentState;
        if (chatbot == null) return;
        if (chatbot.isListening) {
          chatbot.stopVoiceInput();
        } else {
          chatbot.startVoiceInput();
        }
      case 2:
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Account tab has no volume action',
          TextDirection.ltr,
        );
    }
  }

  String _tabName(int index) {
    const names = ['Camera', 'Chat', 'Account'];
    return names[index];
  }

  @override
  void dispose() {
    _volumeSubscription?.cancel();
    super.dispose();
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

      // == INITIALISATION PLACEHOLDER ==
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
      await _signOutGoogleAccount();
      if (!mounted) return;
      await _ensureGoogleAuth();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isGoogleAuthenticated = false;
        _authMessage = 'Google sign-out failed: $error';
      });
    }
  }

  Future<void> _signOutGoogleAccount() async {
    if (_isSigningIn) return;

    setState(() {
      _isSigningIn = true;
      _authMessage = null;
    });

    try {
      await GoogleAuthService.instance.signOut();
      if (!mounted) return;
      setState(() {
        _isGoogleAuthenticated = false;
        _isSigningIn = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSigningIn = false;
        _authMessage = 'Google sign-out failed: $error';
      });
      rethrow;
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
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Account'),
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
              if (isReady &&
                  _camera != null &&
                  _agentSession != null &&
                  _detector != null)
                  IndexedStack(
                  index: _selectedIndex,
                  children: [
                    Semantics(
                      // Tells the OS this is a distinct container/pane
                      namesRoute: true,
                      label: '${_tabName(0)} tab',
                      child: _screens[0],
                    ),
                    Semantics(
                      namesRoute: true,
                      label: '${_tabName(1)} tab',
                      child: _screens[1],
                    ),
                    Semantics(
                      namesRoute: true,
                      label: '${_tabName(2)} tab',
                      child: _screens[2],
                    ),
                  ],
                ),
                if (!(isReady &&
                  _camera != null &&
                  _agentSession != null &&
                  _detector != null))
                _InitializationView(
                stageLabel: _stageLabel(),
                initError: _initError,
                isDownloading: _stage == _InitStage.modelDownload,
                downloadProgress: _downloadProgress,
              ),
              
    );
  }
}

class _InitializationView extends StatelessWidget {
  const _InitializationView({
    required this.stageLabel,
    required this.initError,
    required this.isDownloading,
    required this.downloadProgress,
  });

  final String stageLabel;
  final String? initError;
  final bool isDownloading;
  final double? downloadProgress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child:
            initError != null
                ? Text(
                  initError!,
                  style: const TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                )
                : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(stageLabel, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    if (isDownloading)
                      SizedBox(
                        width: 240,
                        child: LinearProgressIndicator(value: downloadProgress),
                      )
                    else
                      const CircularProgressIndicator(),
                  ],
                ),
      ),
    );
  }
}
