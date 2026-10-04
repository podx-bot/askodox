import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';
import '../../core/flags/askodox_remote_flags.dart';
import '../../core/providers/backend_providers.dart';

/// Staff Workspace + Early Access + feedback, all from the SAME backend.
///
/// * A staff member signs in to ASKODOX normally (their own OTP-verified
///   number). If that number is linked to an ACTIVE staff record the
///   Profile shows "Staff Workspace", which opens ``/staff`` with a one-time
///   2-minute code -- no token is stored or typed on the phone.
/// * "Share → ASKODOX" from any app hands the link to the workspace (staff)
///   or to the chat (everyone else).
/// * Early Access and its label / feedback prompt come from the Command
///   Center; when the call fails the app simply behaves as a normal build.
class EarlyAccessInfo {
  const EarlyAccessInfo({required this.active, this.label = '', this.freeTrial = false,
      this.feedbackPrompt = false, this.consentText = ''});

  static const inactive = EarlyAccessInfo(active: false);

  factory EarlyAccessInfo.fromJson(Map<String, Object?> json) => EarlyAccessInfo(
        active: json['active'] == true,
        label: '${json['label'] ?? 'Early Access'}',
        freeTrial: json['free_trial'] == true,
        feedbackPrompt: json['feedback_prompt'] == true,
        consentText: '${json['consent_text'] ?? ''}',
      );

  final bool active;
  final String label;
  final bool freeTrial;
  final bool feedbackPrompt;
  final String consentText;
}

class AskodoxStaffRepository {
  AskodoxStaffRepository(this._client, this._baseUrl);

  final ApiClient _client;
  final Uri? _baseUrl;
  static const _timeout = ApiRequestOptions(timeout: Duration(seconds: 8));

  ApiRequestOptions _auth(String? token) =>
      ApiRequestOptions(timeout: _timeout.timeout, authToken: token);

  bool _signedIn(String? token) => token != null && token.isNotEmpty && token != 'OTP_VERIFIED';

  /// True only when the server says this signed-in number is staff.
  Future<bool> isStaff(String? token) async {
    if (!_signedIn(token)) return false;
    final result = await _client.get<Map<String, Object?>>('/api/staff/me', options: _auth(token));
    return result is ApiSuccess<Map<String, Object?>> && result.data['staff'] == true;
  }

  /// ``/staff`` with a one-time sign-in code (and an optional shared link).
  Future<Uri?> workspaceUri(String? token, {String? sharedUrl, String type = 'product'}) async {
    final base = _baseUrl;
    if (base == null || !_signedIn(token)) return null;
    final result = await _client.post<Map<String, Object?>>('/api/staff/handoff', options: _auth(token));
    if (result is! ApiSuccess<Map<String, Object?>>) return null;
    final code = '${result.data['code'] ?? ''}';
    if (code.isEmpty) return null;
    final fragment = Uri(queryParameters: {
      'code': code,
      if (sharedUrl != null && sharedUrl.isNotEmpty) 'url': sharedUrl,
      if (sharedUrl != null && sharedUrl.isNotEmpty) 'type': type,
    }).query;
    return base.replace(path: '/staff', fragment: fragment);
  }

  Future<EarlyAccessInfo> earlyAccess({required String installId, required String role, String city = '',
      String? token}) async {
    try {
      final query = Uri(queryParameters: {'install_id': installId, 'role': role, 'city': city}).query;
      final result = await _client.get<Map<String, Object?>>('/api/early-access?$query',
          options: _auth(_signedIn(token) ? token : null));
      if (result is ApiSuccess<Map<String, Object?>>) return EarlyAccessInfo.fromJson(result.data);
    } catch (_) {
      // Early Access never blocks the app.
    }
    return EarlyAccessInfo.inactive;
  }

  /// Sends a report; returns the server reference, or null when it failed.
  Future<String?> sendFeedback({required String kind, required String message, String feature = '',
      String appVersion = '', String installId = '', bool consentDiagnostics = false,
      Map<String, String> diagnostics = const {}, String? token}) async {
    final result = await _client.post<Map<String, Object?>>('/api/feedback',
        body: {
          'kind': kind,
          'message': message,
          'feature': feature,
          'app_version': appVersion,
          'platform': 'android',
          'install_id': installId,
          'consent_diagnostics': consentDiagnostics,
          if (consentDiagnostics) 'diagnostics': diagnostics,
        },
        options: _auth(_signedIn(token) ? token : null));
    return result is ApiSuccess<Map<String, Object?>> ? '${result.data['reference'] ?? ''}' : null;
  }
}

final askodoxStaffRepositoryProvider = Provider<AskodoxStaffRepository>((ref) {
  return AskodoxStaffRepository(ref.watch(apiClientProvider), ref.watch(appConfigProvider).apiBaseUrl);
});

String? _token(Ref ref) => ref.watch(authSessionProvider).tokenPlaceholder;

final askodoxIsStaffProvider = FutureProvider<bool>((ref) async {
  try {
    return await ref.watch(askodoxStaffRepositoryProvider).isStaff(_token(ref));
  } catch (_) {
    return false;
  }
});

final askodoxEarlyAccessProvider = FutureProvider<EarlyAccessInfo>((ref) async {
  final session = ref.watch(authSessionProvider);
  try {
    final id = await ref.watch(askodoxFlagsRepositoryProvider).installId();
    final role = session.user == null ? 'guest' : askodoxFlagRole(session.user!.role);
    return await ref.watch(askodoxStaffRepositoryProvider).earlyAccess(
        installId: id, role: role, token: session.tokenPlaceholder);
  } catch (_) {
    return EarlyAccessInfo.inactive;
  }
});

/// First https link in shared text ("Look at this https://..." from any app).
String? askodoxSharedLink(String text) {
  final match = RegExp(r'https://[^\s<>"]+').firstMatch(text);
  return match?.group(0)?.replaceAll(RegExp(r'[).,;!?]+$'), '');
}

/// Text another app shared to ASKODOX (Android "Share"), read once.
Future<String?> askodoxTakeSharedText([MethodChannel? channel]) async {
  try {
    final text = await (channel ?? const MethodChannel('com.askodox.app/device')).invokeMethod<String>('takeSharedText');
    return text == null || text.trim().isEmpty ? null : text.trim();
  } catch (_) {
    return null; // older native build: nothing shared
  }
}

class StaffWorkspaceScreen extends StatefulWidget {
  const StaffWorkspaceScreen({required this.uri, super.key});

  final Uri uri;

  @override
  State<StaffWorkspaceScreen> createState() => _StaffWorkspaceScreenState();
}

class _StaffWorkspaceScreenState extends State<StaffWorkspaceScreen> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (request) {
      // Stay on the ASKODOX workspace; other links are not opened inside it.
      final target = Uri.tryParse(request.url);
      return target != null && target.host == widget.uri.host
          ? NavigationDecision.navigate
          : NavigationDecision.prevent;
    }))
    ..loadRequest(widget.uri);

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'స్టాఫ్ వర్క్‌స్పేస్' : 'Staff Workspace')),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}

/// Opens the workspace (optionally with a shared link). Returns false when
/// this person is not staff or the server could not be reached.
Future<bool> openStaffWorkspace(BuildContext context, WidgetRef ref, {String? sharedUrl}) async {
  final uri = await ref.read(askodoxStaffRepositoryProvider)
      .workspaceUri(ref.read(authSessionProvider).tokenPlaceholder, sharedUrl: sharedUrl);
  if (uri == null || !context.mounted) return false;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StaffWorkspaceScreen(uri: uri)));
  return true;
}
