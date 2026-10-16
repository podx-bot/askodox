import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/backend_providers.dart';
import '../../services/in_app_messaging.dart';
import '../../services/push_registration.dart';

/// Developer Diagnostics exists only in development builds: debug builds, or
/// a build made with --dart-define=ASKODOX_DEV_DIAGNOSTICS=true. Production
/// release builds never show the entry and the route sends everyone home.
const bool askodoxDiagnosticsBuildFlag = bool.fromEnvironment('ASKODOX_DEV_DIAGNOSTICS');
const String _appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'development');

bool get askodoxDiagnosticsAllowed =>
    _appEnv != 'production' && (kDebugMode || askodoxDiagnosticsBuildFlag);

/// FCM registration token + Firebase Installation ID of THIS phone, to target
/// ONE development device from the Firebase Console ("Send test message" /
/// In-App Messaging "Test on device"). Tokens are shown masked until asked,
/// copied only on tap, and never written to any log.
class AskodoxDeveloperDiagnosticsScreen extends ConsumerStatefulWidget {
  const AskodoxDeveloperDiagnosticsScreen({super.key});

  @override
  ConsumerState<AskodoxDeveloperDiagnosticsScreen> createState() => _AskodoxDeveloperDiagnosticsScreenState();
}

class _AskodoxDeveloperDiagnosticsScreenState extends ConsumerState<AskodoxDeveloperDiagnosticsScreen> {
  String? _token;
  String? _installationId;
  AskodoxPushState? _state;
  bool _reveal = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final push = ref.read(askodoxPushRegistrationProvider);
    AskodoxPushState? state;
    String? token, fid;
    try {
      state = await push.sync();
      token = await push.currentToken();
      fid = await ref.read(askodoxPushBackendProvider).installationId();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _state = state;
      _token = token;
      _installationId = fid;
      _loading = false;
    });
  }

  String _masked(String value) =>
      _reveal || value.length < 16 ? value : '${value.substring(0, 6)}…${value.substring(value.length - 6)}';

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  @override
  Widget build(BuildContext context) {
    if (!askodoxDiagnosticsAllowed) {
      return const Scaffold(body: Center(child: Text('Not available in this build.')));
    }
    final signedIn = ref.watch(authSessionProvider).user != null;
    Widget row(String key, String label, String? value) => ListTile(
          key: Key(key),
          title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: SelectableText(value == null ? 'Not available' : _masked(value)),
          trailing: value == null
              ? null
              : IconButton(icon: const Icon(Icons.copy_rounded), tooltip: 'Copy', onPressed: () => _copy(label, value)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Developer Diagnostics')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(12), children: [
              const Card(
                color: Color(0xFFFFF4E5),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                      'Development builds only. Use these values to send a Firebase Console test to THIS phone only. '
                      'Never share them publicly and never send a campaign to all users while testing.'),
                ),
              ),
              ListTile(
                key: const Key('askodoxDiagFirebase'),
                title: const Text('Firebase in this build', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(AskodoxFirebaseConfig.configured
                    ? 'Configured (project ${AskodoxFirebaseConfig.projectId})'
                    : 'Not configured: FIREBASE_* build values are missing'),
              ),
              ListTile(
                key: const Key('askodoxDiagPushState'),
                title: const Text('Push registration', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(signedIn ? (_state?.name ?? 'unknown') : 'Sign in to register this phone'),
              ),
              row('askodoxDiagFcmToken', 'FCM registration token', _token),
              row('askodoxDiagInstallationId', 'Firebase Installation ID', _installationId),
              SwitchListTile(
                key: const Key('askodoxDiagReveal'),
                title: const Text('Show full values'),
                value: _reveal,
                onChanged: (on) => setState(() => _reveal = on),
              ),
              FutureBuilder<bool>(
                future: ref.read(askodoxInAppMessagingProvider).optedIn(),
                builder: (context, snap) => ListTile(
                  title: const Text('In-App Messaging opt-in', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(snap.data == true ? 'On' : 'Off (Notifications -> Offer messages in the app)'),
                ),
              ),
              TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh_rounded), label: const Text('Refresh')),
            ]),
    );
  }
}
