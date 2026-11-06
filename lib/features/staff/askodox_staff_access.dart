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
  /// The hidden browser that reads a store page, kept ATTACHED under the
  /// workspace (a detached Android WebView may not finish loading).
  WebViewController? _reader;

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
      final url = Uri.parse('${ask['url']}');
      final page = await askodoxReadStoreBest(url, host: (reader) {
        if (mounted) setState(() => _reader = reader);
      });
      result = {
        'ok': true,
        'html': askodoxCompactStoreHtml(page.html),
        'final_url': page.finalUrl.toString(),
        'product': askodoxLooksLikeProductPage(page.html),
      };
    } catch (error) {
      result = {'ok': false, 'error': askodoxReadFailureText(error)};
    }
    if (!mounted) return;
    await _controller.runJavaScript('window.askodoxPageRead && window.askodoxPageRead(${jsonEncode(id)}, ${jsonEncode(result)})');
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'స్టాఫ్ వర్క్‌స్పేస్' : 'Staff Workspace')),
      body: SafeArea(
        child: Stack(children: [
          // Under the workspace and never touchable: it only reads a store page.
          if (_reader != null)
            Positioned.fill(child: IgnorePointer(child: WebViewWidget(controller: _reader!))),
          Positioned.fill(child: WebViewWidget(controller: _controller)),
        ]),
      ),
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

/// A desktop browser: store invite links often send a PHONE browser to the
/// store's app (intent:// / meesho://), which a WebView cannot open.
const _desktopBrowserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

final _ldProduct = RegExp(r'"@type"\s*:\s*"Product"');
final _ogProduct = RegExp(r'''property=["']og:type["'][^>]*content=["']product''', caseSensitive: false);
final _priceMeta = RegExp(r'(product:price:amount|og:price:amount)', caseSensitive: false);
final _storeJson = RegExp(r'"(min_product_price|product_images|catalog_name|product_name)"');

/// True when [html] carries the product's own data (schema.org Product,
/// og product tags, or a store's embedded product JSON) -- not just an
/// invite / "open in app" page.
bool askodoxLooksLikeProductPage(String html) {
  final h = html.length > 3000000 ? html.substring(0, 3000000) : html;
  if (_ldProduct.hasMatch(h) || _ogProduct.hasMatch(h) || _priceMeta.hasMatch(h)) return true;
  return h.contains('__NEXT_DATA__') && _storeJson.hasMatch(h);
}

/// The https page an Android `intent://...;S.browser_fallback_url=...;end` link offers.
Uri? askodoxIntentFallback(String link) {
  final m = RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(link);
  if (m == null) return null;
  final target = Uri.tryParse(Uri.decodeComponent(m.group(1)!));
  return target != null && target.scheme == 'https' ? target : null;
}

final _headTags = RegExp(r'''<title[^>]*>.*?</title>|<meta[^>]+>|<link[^>]+rel=["']canonical[^>]*>''',
    caseSensitive: false, dotAll: true);
final _dataScripts =
    RegExp(r'<script[^>]*(application/ld\+json|__NEXT_DATA__)[^>]*>.*?</script>', caseSensitive: false, dotAll: true);

/// Only what the server reads (meta / title / canonical / JSON-LD / embedded
/// store JSON) when a rendered page is too big to send whole.
String askodoxCompactStoreHtml(String html, {int max = 1800000}) {
  if (html.length <= max) return html;
  final out = StringBuffer('<html><head>');
  for (final m in _headTags.allMatches(html)) {
    out.write(m.group(0));
  }
  for (final m in _dataScripts.allMatches(html)) {
    out.write(m.group(0));
  }
  out.write('</head><body></body></html>');
  final compact = out.toString();
  return compact.length <= max ? compact : compact.substring(0, max);
}

/// A short reason the staff member can act on (shown on the workspace page).
String askodoxReadFailureText(Object error) {
  if (error is TimeoutException) return 'timeout';
  if (error is HttpException) return error.message;
  if (error is SocketException) return 'no internet';
  if (error is FormatException) return error.message;
  return error.runtimeType.toString();
}

/// Android hands JavaScript results back JSON-encoded (`"\"<html>...\""`).
Object? _jsValue(Object raw) {
  if (raw is String && raw.startsWith('"')) {
    try {
      return jsonDecode(raw);
    } catch (_) {}
  }
  return raw;
}

const _productLinkJs = '(function(){var a=document.querySelector(\'a[href*="/p/"]\');return a?a.href:"";})()';

/// The same page loaded in a hidden browser engine (JavaScript runs, cookies
/// and redirects behave like a real browser). It waits, page after page, until
/// the product's data is in the page -- an invite page that forwards by script
/// is followed -- and app links (intent:// / meesho://) are never opened.
/// [host] gets the browser while it reads (to keep it attached) and null after.
Future<AskodoxStorePage> askodoxReadStoreInBrowser(Uri url,
    {Duration limit = const Duration(seconds: 45), void Function(WebViewController? reader)? host}) async {
  if (url.scheme != 'https') throw const FormatException('https only');
  final done = Completer<AskodoxStorePage>();
  AskodoxStorePage? last;
  Object? lastError;
  var followed = 0;
  late final WebViewController browser;

  Future<void> look() async {
    if (done.isCompleted) return;
    try {
      final raw = _jsValue(await browser.runJavaScriptReturningResult('document.documentElement.outerHTML'));
      final html = raw is String ? raw : '$raw';
      final current = Uri.tryParse(await browser.currentUrl() ?? '') ?? url;
      if (current.scheme == 'https' && html.length > 200) last = AskodoxStorePage(html, current);
      if (askodoxLooksLikeProductPage(html)) {
        if (!done.isCompleted) done.complete(AskodoxStorePage(html, current));
        return;
      }
      // An invite page that only LINKS to the product: open that link (twice at most).
      if (followed < 2) {
        final link = _jsValue(await browser.runJavaScriptReturningResult(_productLinkJs));
        final target = Uri.tryParse('${link ?? ''}');
        if (target != null && target.scheme == 'https' && target.host == current.host && target != current) {
          followed++;
          await browser.loadRequest(target);
        }
      }
    } catch (error) {
      lastError = error;
    }
  }

  browser = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setUserAgent(_desktopBrowserAgent)
    ..setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (request) {
        final target = Uri.tryParse(request.url);
        if (target != null && target.scheme == 'https') return NavigationDecision.navigate;
        final fallback = askodoxIntentFallback(request.url);
        if (fallback != null) unawaited(browser.loadRequest(fallback));
        return NavigationDecision.prevent; // never leave for the store's app / Play Store
      },
      onPageFinished: (_) => unawaited(look()),
      onWebResourceError: (error) {
        if (error.isForMainFrame == true) {
          lastError = HttpException('page load failed: ${error.errorCode}', uri: url);
        }
      },
    ));
  host?.call(browser);
  // Pages that fill themselves by script after "finished": look again every 2 s.
  final poll = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(look()));
  try {
    await browser.loadRequest(url);
    return await done.future.timeout(limit);
  } on TimeoutException {
    // Not clearly a product page: hand back what loaded; the server decides.
    final page = last;
    if (page != null) return page;
    throw lastError ?? TimeoutException('store page did not load', limit);
  } finally {
    poll.cancel();
    host?.call(null);
  }
}

/// Both readers at once (plain phone request + hidden browser). The first one
/// that holds the product's data wins; otherwise the longest page that loaded.
Future<AskodoxStorePage> askodoxReadStoreBest(Uri url,
    {void Function(WebViewController? reader)? host,
    Future<AskodoxStorePage> Function(Uri url)? plain,
    Future<AskodoxStorePage> Function(Uri url)? browser}) {
  final readers = <Future<AskodoxStorePage>>[
    (plain ?? askodoxReadStorePage)(url),
    (browser ?? ((u) => askodoxReadStoreInBrowser(u, host: host)))(url),
  ];
  final done = Completer<AskodoxStorePage>();
  final pages = <AskodoxStorePage>[];
  Object? lastError;
  var left = readers.length;
  void finishOne() {
    left--;
    if (left > 0 || done.isCompleted) return;
    if (pages.isEmpty) {
      done.completeError(lastError ?? StateError('no reader answered'));
      return;
    }
    pages.sort((a, b) => b.html.length.compareTo(a.html.length));
    done.complete(pages.first);
  }

  for (final reader in readers) {
    unawaited(reader.then((page) {
      pages.add(page);
      if (!done.isCompleted && askodoxLooksLikeProductPage(page.html)) done.complete(page);
      finishOne();
    }, onError: (Object error) {
      lastError = error;
      finishOne();
    }));
  }
  return done.future;
}

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
