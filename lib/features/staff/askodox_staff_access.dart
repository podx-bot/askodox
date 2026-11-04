import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

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
    // Stores such as Meesho refuse our server but not a phone: the workspace
    // page asks the app to read a product page with THIS phone's connection.
    ..addJavaScriptChannel('AskodoxPageReader', onMessageReceived: (m) => unawaited(_readForPage(m.message)))
    ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (request) {
      // Stay on the ASKODOX workspace; other links are not opened inside it.
      final target = Uri.tryParse(request.url);
      return target != null && target.host == widget.uri.host
          ? NavigationDecision.navigate
          : NavigationDecision.prevent;
    }))
    ..loadRequest(widget.uri);

  @override
  void initState() {
    super.initState();
    // Android WebView opens NO chooser for <input type=file> unless the app
    // answers it: Camera / Gallery in the workspace did nothing (owner, 2026-11-04).
    final platform = _controller.platform;
    if (platform is AndroidWebViewController) {
      unawaited(platform.setOnShowFileSelector(askodoxPickFilesForWebPage));
    }
  }

  Future<void> _readForPage(String message) async {
    Object? id;
    Map<String, Object?> result;
    try {
      final ask = jsonDecode(message) as Map<String, dynamic>;
      id = ask['id'];
      final page = await askodoxReadStorePage(Uri.parse('${ask['url']}'));
      result = {'ok': true, 'html': page.html, 'final_url': page.finalUrl.toString()};
    } catch (error) {
      result = {'ok': false, 'error': error.runtimeType.toString()};
    }
    if (!mounted) return;
    await _controller.runJavaScript('window.askodoxPageRead && window.askodoxPageRead(${jsonEncode(id)}, ${jsonEncode(result)})');
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'స్టాఫ్ వర్క్‌స్పేస్' : 'Staff Workspace')),
      body: SafeArea(child: WebViewWidget(controller: _controller)),
    );
  }
}

/// Photos for an `<input type=file>` in a web page: the camera when the page
/// asks for capture, else the gallery (several when allowed). Re-encoded as
/// JPEG <= 2000 px so uploads stay small. Returns file:// URIs (none = cancelled).
Future<List<String>> askodoxPickFilesForWebPage(FileSelectorParams params, {ImagePicker? picker}) async {
  final pick = picker ?? ImagePicker();
  try {
    if (params.isCaptureEnabled) {
      final shot = await pick.pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2000);
      return shot == null ? const [] : [Uri.file(shot.path).toString()];
    }
    if (params.mode == FileSelectorMode.openMultiple) {
      final many = await pick.pickMultiImage(imageQuality: 85, maxWidth: 2000);
      return [for (final f in many) Uri.file(f.path).toString()];
    }
    final one = await pick.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 2000);
    return one == null ? const [] : [Uri.file(one.path).toString()];
  } catch (_) {
    return const []; // permission denied / no camera: the page simply gets no file
  }
}

/// A product page as THIS phone reads it (a normal mobile browser request,
/// redirects and one meta-refresh followed). https only, 2 MB, 15 s.
class AskodoxStorePage {
  const AskodoxStorePage(this.html, this.finalUrl);
  final String html;
  final Uri finalUrl;
}

const _phoneBrowserAgent =
    'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';

Future<AskodoxStorePage> askodoxReadStorePage(Uri url,
    {HttpClient Function()? client, int maxBytes = 2000000}) async {
  var target = url;
  final http = (client ?? HttpClient.new)()..connectionTimeout = const Duration(seconds: 10);
  try {
    for (var hop = 0; hop < 2; hop++) {
      if (target.scheme != 'https') throw const FormatException('https only');
      final request = await http.getUrl(target);
      request.followRedirects = true;
      request.maxRedirects = 6;
      request.headers
        ..set(HttpHeaders.userAgentHeader, _phoneBrowserAgent)
        ..set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml')
        ..set(HttpHeaders.acceptLanguageHeader, 'en-IN,en;q=0.9');
      final response = await request.close().timeout(const Duration(seconds: 15));
      for (final hopInfo in response.redirects) {
        target = target.resolveUri(hopInfo.location);
      }
      if (response.statusCode >= 400) throw HttpException('HTTP ${response.statusCode}', uri: target);
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        bytes.addAll(chunk);
        if (bytes.length > maxBytes) break;
      }
      final html = utf8.decode(bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes, allowMalformed: true);
      final refresh = askodoxMetaRefreshTarget(html, target);
      if (refresh == null || hop == 1) return AskodoxStorePage(html, target);
      target = refresh; // an invite page that forwards to the product page
    }
    throw StateError('unreachable');
  } finally {
    http.close(force: true);
  }
}

/// `<meta http-equiv="refresh" content="0; url=...">` -> the https target.
Uri? askodoxMetaRefreshTarget(String html, Uri base) {
  final tag = RegExp(r'''<meta[^>]+http-equiv=["']?refresh["']?[^>]*>''', caseSensitive: false).firstMatch(html);
  if (tag == null) return null;
  final url = RegExp(r'''url\s*=\s*['"]?([^'">\s]+)''', caseSensitive: false).firstMatch(tag.group(0)!);
  if (url == null) return null;
  final target = base.resolve(url.group(1)!.replaceAll('&amp;', '&'));
  return target.scheme == 'https' ? target : null;
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
