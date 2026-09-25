import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Handles Google Sign-In and produces authenticated googleapis clients
// (Calendar, Gmail) for use by the chatbot's tools.
//
// Uses extension_google_sign_in_as_googleapis_auth 3.x, where the
// authenticated client comes from the authorization object returned by
// authorizationForScopes (authorization.authClient(scopes: ...)), not from
// GoogleSignIn directly. Earlier versions of this package exposed
// GoogleSignIn.authenticatedClient() instead — if you're pinned to an older
// version, adjust accordingly.
class GoogleAuthService {
  GoogleAuthService._();
  static final GoogleAuthService instance = GoogleAuthService._();

  static const List<String> scopes = [
    // == SCOPE PLACEHOLDER ==
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _initialized = false;
  auth.AuthClient? _authClient;
  GoogleSignInAccount? _account;

  GoogleSignInAccount? get account => _account;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    final serverClientId = dotenv.env['GOOGLE_SERVER_CLIENT_ID'];

    if (serverClientId == null || serverClientId.isEmpty) {
      throw StateError(
        'GOOGLE_SERVER_CLIENT_ID is missing. Add it to .env or pass it with '
        '--dart-define=GOOGLE_SERVER_CLIENT_ID=...',
      );
    }

    await _googleSignIn.initialize(serverClientId: serverClientId);
    _initialized = true;
  }

  // Signs the user in (reusing an existing session where possible), makes
  // sure the required scopes are granted, and returns an authenticated HTTP
  // client that can back any googleapis API class.
  Future<auth.AuthClient> getAuthenticatedClient() async {
    if (_authClient != null) return _authClient!;

    await _ensureInitialized();

    GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.attemptLightweightAuthentication();
    } catch (_) {
      account = null;
    }
    account ??= await _googleSignIn.authenticate();
    _account = account;

    final authorization =
        await account.authorizationClient.authorizationForScopes(scopes) ??
        // A null result means the scopes need user interaction. Request them
        // from the button handler instead of treating that as a denial.
        await account.authorizationClient.authorizeScopes(scopes);

    // authClient() lives on the authorization object in the current
    // extension package version, not on GoogleSignIn itself.
    final client = authorization.authClient(scopes: scopes);

    _authClient = client;
    return client;
  }

  Future<void> signOut() async {
    await _ensureInitialized();
    await _googleSignIn.signOut();
    _authClient = null;
    _account = null;
  }

  // Call this if a tool call fails with an auth error, to force a fresh
  // sign-in / re-authorization on the next request instead of reusing a
  // possibly-expired client.
  void invalidateClient() {
    _authClient = null;
  }
}
