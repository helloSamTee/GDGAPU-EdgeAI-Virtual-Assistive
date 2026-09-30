import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AccountPage extends StatelessWidget {
  const AccountPage({
    super.key,
    required this.account,
    required this.isSigningIn,
    required this.isAuthenticated,
    required this.message,
    required this.onSignIn,
    required this.onSignOut,
    required this.onSwitchAccount,
  });

  final GoogleSignInAccount? account;
  final bool isSigningIn;
  final bool isAuthenticated;
  final String? message;
  final VoidCallback onSignIn;
  final Future<void> Function() onSignOut;
  final Future<void> Function() onSwitchAccount;

  @override
  Widget build(BuildContext context) {
    final displayName = account?.displayName ?? account?.email ?? 'No account';

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
      children: [
        Text('Account', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'Manage the Google account used by calendar and email tools.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage:
                      account?.photoUrl == null
                          ? null
                          : NetworkImage(account!.photoUrl!),
                  child:
                      account?.photoUrl == null
                          ? const Icon(Icons.person, size: 30)
                          : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (account?.displayName != null) ...[
                        const SizedBox(height: 4),
                        Text(account!.email),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        isAuthenticated ? 'Signed in' : 'Signed out',
                        style: TextStyle(
                          color:
                              isAuthenticated
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 16),
          Text(message!, style: const TextStyle(color: Colors.orangeAccent)),
        ],
        const SizedBox(height: 24),
        if (isSigningIn)
          const Center(child: CircularProgressIndicator())
        else if (!isAuthenticated)
          FilledButton.icon(
            onPressed: onSignIn,
            icon: const Icon(Icons.login),
            label: const Text('Sign in with Google'),
          )
        else ...[
          OutlinedButton.icon(
            onPressed: onSwitchAccount,
            icon: const Icon(Icons.switch_account),
            label: const Text('Switch account'),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
        ],
      ],
    );
  }
}
