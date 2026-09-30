import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/providers/backend_providers.dart';

/// ASKODOX Screen Guide (Android): step-by-step guidance in OTHER apps.
///
/// * Opt-in twice: the Owner's feature flag (server) and the user's own
///   Android accessibility switch. Nothing is read unless the user started a
///   guide here.
/// * Privacy Shield: password / OTP / PIN / UPI PIN / CVV / card / bank /
///   Aadhaar screens and payment apps PAUSE the guide on the phone before
///   anything is sent; resume is explicit (double-tap or Continue).
/// * The user performs every step; ASKODOX only shows / says what to press.
/// * End Guide clears the session everywhere; no screenshots are ever taken.
const screenGuidePauseMessage =
    'Sensitive information detected. ASKODOX screen assistance is paused. Please complete this step yourself. '
    'When finished and you leave this sensitive screen, double-tap ASKODOX or press Continue to resume.';

enum ScreenGuidePhase {
  unavailable,
  notIncluded,
  disabled,
  needsConsent,
  needsAccessibility,
  ready,
  starting,
  active,
  privacyPaused,
  ended,
  error,
}

/// The disclosure version the user must accept (the server checks it too).
const screenGuideConsentVersion = 'sg-disclosure-v1';
const _consentKey = 'askodox.screen_guide.consent';

/// Shown BEFORE ASKODOX sends anyone to Android's Accessibility settings.
const screenGuideDisclosureTitle = 'Screen Guide: how it works';
const screenGuideDisclosure = [
  'What it does: while YOU run a guide, ASKODOX shows and says which button to press next in another app. '
      'You press every button yourself; ASKODOX never taps, types, pays or changes settings for you.',
  'Why it needs access: Android only lets a helper see the names of buttons on screen through the '
      'Accessibility service "ASKODOX Screen Guide". It is off until you switch it on.',
  'What it reads: only the visible button and label text of the app you are in, and only while a guide is '
      'running. It never reads what you type into fields and never takes screenshots.',
  'What is sent: the visible labels of the current screen and your goal are sent to ASKODOX servers and '
      'its AI to work out the next step. They are not stored; only anonymous counts are kept.',
  'Processed on your phone: the Privacy Shield checks every screen first. Password, OTP, PIN, UPI PIN, CVV, '
      'card, bank, Aadhaar/ID screens and payment or banking apps are never read or sent: the guide pauses.',
  'Never collected: passwords, codes, PINs, card or bank details, ID numbers, messages, photos, contacts.',
  'You are in control: Continue / double-tap resumes after a pause, End Guide stops it and clears the '
      'session. Turn the permission off any time in Android Settings > Accessibility > ASKODOX Screen Guide.',
];

Future<bool> screenGuideConsented() async {
  try {
    return (await SharedPreferences.getInstance()).getString(_consentKey) == screenGuideConsentVersion;
  } catch (_) {
    return false;
  }
}

Future<void> screenGuideRecordConsent(bool agreed) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (agreed) {
      await prefs.setString(_consentKey, screenGuideConsentVersion);
    } else {
      await prefs.remove(_consentKey);
    }
  } catch (_) {}
}

class ScreenGuideState {
  const ScreenGuideState(this.phase, {this.message, this.instruction, this.sessionId});

  final ScreenGuidePhase phase;
  final String? message;
  final String? instruction;
  final String? sessionId;

  ScreenGuideState copyWith({ScreenGuidePhase? phase, String? message, String? instruction, String? sessionId}) =>
      ScreenGuideState(phase ?? this.phase,
          message: message ?? this.message,
          instruction: instruction ?? this.instruction,
          sessionId: sessionId ?? this.sessionId);
}

/// The same words the phone and server treat as sensitive -- used here to
/// stop a user from typing a code or password into the guide's goal.
final _sensitive = RegExp(
  r'(\botp\b|one[\s-]?time[\s-]?pass|\bpassword\b|\bpasscode\b|\bpin\b|\bmpin\b|upi[\s-]?pin|\bcvv\b|\bcvc\b|'
  r'card number|\baadhaa?r\b|ఓటీపీ|పాస్‌?వర్డ్|పిన్|ఆధార్|ओटीपी|पासवर्ड|पिन|आधार|\b\d{4,}\b)',
  caseSensitive: false,
);

/// Null when the goal is fine, else why it can't be used.
String? screenGuideGoalProblem(String goal) {
  final g = goal.trim();
  if (g.length < 2) return 'Tell ASKODOX what you want to do.';
  if (_sensitive.hasMatch(g)) {
    return 'Please do not type codes, PINs, passwords or ID numbers. Describe the task only (e.g. "turn on Wi-Fi").';
  }
  return null;
}

class ScreenGuideNative {
  const ScreenGuideNative([this._channel = const MethodChannel('com.askodox.app/device')]);

  final MethodChannel _channel;

  Future<Map<String, Object?>> status() async {
    try {
      return await _channel.invokeMapMethod<String, Object?>('screenGuideStatus') ?? const {};
    } catch (_) {
      return const {}; // not Android / older build
    }
  }

  Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod<bool>('openAccessibilitySettings');
    } catch (_) {}
  }

  Future<bool> start(Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<bool>('startScreenGuide', args) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> resume() async {
    try {
      await _channel.invokeMethod<bool>('resumeScreenGuide');
    } catch (_) {}
  }

  Future<void> stop(String outcome) async {
    try {
      await _channel.invokeMethod<bool>('stopScreenGuide', {'outcome': outcome});
    } catch (_) {}
  }
}

class ScreenGuideApi {
  ScreenGuideApi({http.Client? client, String? baseUrl})
      : _client = client,
        baseUrl = baseUrl ?? _defaultBase;

  static const _defaultBase = String.fromEnvironment(
    'ASKODOX_API_BASE_URL',
    defaultValue: 'https://podx-ai-connect-production-3279.up.railway.app',
  );

  final http.Client? _client;
  final String baseUrl;

  Future<Map<String, Object?>?> _post(String path, Map<String, Object?> body, String token) async {
    final client = _client ?? http.Client();
    try {
      final r = await client
          .post(Uri.parse('$baseUrl/api/companion/guide/$path'),
              headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      final map = decoded is Map ? Map<String, Object?>.from(decoded) : <String, Object?>{};
      return {...map, '_status': r.statusCode};
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<Map<String, Object?>?> start(String goal, String language, Map<String, bool> permissions, String token) =>
      _post('start', {
        'goal': goal,
        'language': language,
        'permissions': permissions,
        'consent_version': screenGuideConsentVersion,
      }, token);

  /// Owner switches (companion / screen guide / accessibility / shield).
  Future<Map<String, Object?>?> status() async {
    final client = _client ?? http.Client();
    try {
      final r = await client.get(Uri.parse('$baseUrl/api/companion/guide/status')).timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } catch (_) {
      return null;
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<void> resume(String sessionId, String token) async => _post('resume', {'session_id': sessionId}, token);

  Future<void> end(String sessionId, String outcome, String token) async =>
      _post('end', {'session_id': sessionId, 'outcome': outcome}, token);
}

class ScreenGuideController extends StateNotifier<ScreenGuideState> {
  ScreenGuideController(this._native, this._api, this._token, {Future<bool> Function()? consented})
      : _consented = consented ?? screenGuideConsented,
        super(const ScreenGuideState(ScreenGuidePhase.ready));

  final ScreenGuideNative _native;
  final ScreenGuideApi _api;
  final String? Function() _token;
  final Future<bool> Function() _consented;

  static const notIncludedMessage =
      'Screen Guide is not part of this test build. Ask in ASKODOX chat for written step-by-step help instead.';

  /// Reads the phone's state (e.g. after coming back to ASKODOX).
  Future<void> refresh() async {
    final s = await _native.status();
    if (s.isEmpty || s['supported'] != true) {
      state = const ScreenGuideState(ScreenGuidePhase.unavailable);
      return;
    }
    if (s['declared'] == false) {
      state = const ScreenGuideState(ScreenGuidePhase.notIncluded, message: notIncludedMessage);
      return;
    }
    final server = await _api.status();
    if (server != null && server['enabled'] == false) {
      state = ScreenGuideState(ScreenGuidePhase.disabled,
          message: '${server['notice'] ?? 'Screen Guide is not available right now.'}');
      return;
    }
    if (!await _consented()) {
      state = const ScreenGuideState(ScreenGuidePhase.needsConsent);
      return;
    }
    if (s['accessibilityEnabled'] != true) {
      state = ScreenGuideState(ScreenGuidePhase.needsAccessibility, sessionId: state.sessionId);
      return;
    }
    state = switch ('${s['state']}') {
      'ACTIVE' => state.copyWith(phase: ScreenGuidePhase.active, instruction: s['instruction'] as String?),
      'PRIVACY_PAUSED' => state.copyWith(phase: ScreenGuidePhase.privacyPaused, message: screenGuidePauseMessage),
      'ENDED' => const ScreenGuideState(ScreenGuidePhase.ended),
      _ => const ScreenGuideState(ScreenGuidePhase.ready),
    };
  }

  Future<void> start(String goal, {String language = 'en', bool voice = true}) async {
    final problem = screenGuideGoalProblem(goal);
    if (problem != null) {
      state = ScreenGuideState(ScreenGuidePhase.error, message: problem);
      return;
    }
    final token = _token();
    if (token == null || token.isEmpty) {
      state = const ScreenGuideState(ScreenGuidePhase.error, message: 'Sign in to use the Screen Guide.');
      return;
    }
    if (!await _consented()) {
      state = const ScreenGuideState(ScreenGuidePhase.needsConsent);
      return;
    }
    final native = await _native.status();
    if (native['declared'] == false) {
      state = const ScreenGuideState(ScreenGuidePhase.notIncluded, message: notIncludedMessage);
      return;
    }
    if (native['accessibilityEnabled'] != true) {
      state = const ScreenGuideState(ScreenGuidePhase.needsAccessibility);
      return;
    }
    state = const ScreenGuideState(ScreenGuidePhase.starting);
    final started = await _api.start(goal.trim(), language,
        {'accessibility_enabled': true, 'voice_on': voice}, token);
    if (started == null) {
      state = const ScreenGuideState(ScreenGuidePhase.error, message: 'Could not reach ASKODOX. Try again.');
      return;
    }
    if (started['_status'] == 503) {
      state = const ScreenGuideState(ScreenGuidePhase.disabled,
          message: 'Screen Guide is not available right now. ASKODOX works normally.');
      return;
    }
    if (started['_status'] == 428) {
      state = const ScreenGuideState(ScreenGuidePhase.needsConsent);
      return;
    }
    final sid = '${started['session_id'] ?? ''}';
    if (sid.isEmpty) {
      state = const ScreenGuideState(ScreenGuidePhase.error, message: 'Could not start the guide.');
      return;
    }
    final ok = await _native.start({
      'sessionId': sid, 'token': token, 'baseUrl': _api.baseUrl, 'language': language, 'voice': voice,
    });
    if (!ok) {
      await _api.end(sid, 'failed', token);
      state = const ScreenGuideState(ScreenGuidePhase.needsAccessibility,
          message: 'Turn on "ASKODOX Screen Guide" in Android Accessibility settings, then try again.');
      return;
    }
    state = ScreenGuideState(ScreenGuidePhase.active, sessionId: sid);
  }

  /// Explicit resume only (the user pressed Continue / double-tapped).
  Future<void> resume() async {
    await _native.resume();
    final sid = state.sessionId;
    final token = _token();
    if (sid != null && token != null) await _api.resume(sid, token);
    state = ScreenGuideState(ScreenGuidePhase.active, sessionId: sid);
  }

  /// End Guide: stops the phone service, ends the server session and clears
  /// everything held here.
  Future<void> end({String outcome = 'abandoned'}) async {
    final sid = state.sessionId;
    await _native.stop(outcome);
    final token = _token();
    if (sid != null && token != null) await _api.end(sid, outcome, token);
    state = const ScreenGuideState(ScreenGuidePhase.ended);
  }

  void markPaused() => state = state.copyWith(phase: ScreenGuidePhase.privacyPaused, message: screenGuidePauseMessage);
}

final screenGuideNativeProvider = Provider<ScreenGuideNative>((ref) => const ScreenGuideNative());
final screenGuideApiProvider = Provider<ScreenGuideApi>((ref) => ScreenGuideApi());

/// Owner switches for companion capabilities (public, no user data). Unknown
/// (offline / older server) = allowed, so ASKODOX never breaks.
final companionCapabilitiesProvider = FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  final status = await ref.watch(screenGuideApiProvider).status();
  final caps = status?['capabilities'];
  if (caps is! Map) return const {};
  return {for (final e in caps.entries) '${e.key}': e.value == true};
});

bool companionAllows(Map<String, bool> caps, String capability) =>
    (caps['enabled'] ?? true) && (caps[capability] ?? true);

final screenGuideProvider = StateNotifierProvider.autoDispose<ScreenGuideController, ScreenGuideState>((ref) {
  return ScreenGuideController(ref.watch(screenGuideNativeProvider), ref.watch(screenGuideApiProvider), () {
    final session = ref.read(authSessionProvider);
    return session.user == null ? null : session.tokenPlaceholder;
  });
});

/// The prominent disclosure. Returns true only on AGREE & CONTINUE. Declining
/// changes nothing else in ASKODOX.
Future<bool> showScreenGuideDisclosure(BuildContext context) async {
  final agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      key: const Key('screenGuideDisclosure'),
      title: const Text(screenGuideDisclosureTitle),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in screenGuideDisclosure)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(line)),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('screenGuideNotNow'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('NOT NOW'),
        ),
        FilledButton(
          key: const Key('screenGuideAgree'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('AGREE & CONTINUE'),
        ),
      ],
    ),
  );
  await screenGuideRecordConsent(agreed == true);
  return agreed == true;
}

class ScreenGuideScreen extends ConsumerStatefulWidget {
  const ScreenGuideScreen({super.key});

  @override
  ConsumerState<ScreenGuideScreen> createState() => _ScreenGuideScreenState();
}

class _ScreenGuideScreenState extends ConsumerState<ScreenGuideScreen> with WidgetsBindingObserver {
  final _goal = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(screenGuideProvider.notifier).refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.read(screenGuideProvider.notifier).refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _goal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final s = ref.watch(screenGuideProvider);
    final c = ref.read(screenGuideProvider.notifier);
    final running = s.phase == ScreenGuidePhase.active || s.phase == ScreenGuidePhase.privacyPaused;
    return Scaffold(
      appBar: AppBar(title: Text(t('Screen Guide', 'స్క్రీన్ గైడ్'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(
          t('ASKODOX guides you step by step in other apps. You press every button yourself. It pauses on '
              'password, OTP, PIN, UPI PIN, card, bank and Aadhaar screens and in payment apps, and never takes '
              'screenshots.',
              'ASKODOX ఇతర యాప్‌లలో దశలవారీగా మార్గనిర్దేశం చేస్తుంది. ప్రతి బటన్‌ను మీరే నొక్కుతారు. పాస్‌వర్డ్, ఓటీపీ, పిన్, '
              'యూపీఐ పిన్, కార్డ్, బ్యాంక్, ఆధార్ స్క్రీన్‌లలో ఆగిపోతుంది. స్క్రీన్‌షాట్‌లు తీయదు.'),
          key: const Key('screenGuideIntro'),
        ),
        const SizedBox(height: 12),
        if (s.phase == ScreenGuidePhase.unavailable)
          Text(t('Available on Android 8 or newer.', 'Android 8 లేదా కొత్తదానిలో అందుబాటులో ఉంది.')),
        if (s.phase == ScreenGuidePhase.notIncluded || s.phase == ScreenGuidePhase.disabled)
          Card(
            key: const Key('screenGuideUnavailable'),
            child: ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: Text(s.message ?? t('Screen Guide is not available.', 'స్క్రీన్ గైడ్ అందుబాటులో లేదు.')),
              subtitle: Text(t('Everything else in ASKODOX works as usual.', 'ASKODOX లో మిగతావన్నీ యథావిధిగా పనిచేస్తాయి.')),
            ),
          ),
        if (s.phase == ScreenGuidePhase.needsConsent)
          Card(
            key: const Key('screenGuideNeedsConsent'),
            child: ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(t('Read how Screen Guide works', 'స్క్రీన్ గైడ్ ఎలా పనిచేస్తుందో చదవండి')),
              subtitle: Text(t('Nothing is switched on until you agree.', 'మీరు అంగీకరించే వరకు ఏదీ ఆన్ కాదు.')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () async {
                if (await showScreenGuideDisclosure(context)) await c.refresh();
              },
            ),
          ),
        if (s.phase == ScreenGuidePhase.needsAccessibility)
          Card(
            key: const Key('screenGuideNeedsAccessibility'),
            child: ListTile(
              leading: const Icon(Icons.accessibility_new_rounded),
              title: Text(t('Turn on "ASKODOX Screen Guide"', '"ASKODOX Screen Guide" ఆన్ చేయండి')),
              subtitle: Text(s.message ??
                  t('Android Settings > Accessibility. You can turn it off any time.',
                      'Android సెట్టింగ్స్ > యాక్సెసిబిలిటీ. ఎప్పుడైనా ఆఫ్ చేయవచ్చు.')),
              trailing: const Icon(Icons.open_in_new_rounded),
              onTap: () async {
                // Never send anyone to Accessibility settings without the disclosure.
                if (!await screenGuideConsented()) {
                  if (!context.mounted || !await showScreenGuideDisclosure(context)) return;
                }
                await ref.read(screenGuideNativeProvider).openAccessibilitySettings();
              },
            ),
          ),
        if (s.phase == ScreenGuidePhase.privacyPaused)
          Card(
            key: const Key('screenGuidePrivacyPaused'),
            color: const Color(0xFFFFF4E5),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('PRIVACY PAUSED', 'గోప్యత కోసం ఆపివేయబడింది'),
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(screenGuidePauseMessage),
              ]),
            ),
          ),
        if (s.phase == ScreenGuidePhase.active && s.instruction != null)
          Card(child: ListTile(leading: const Icon(Icons.touch_app_rounded), title: Text(s.instruction!))),
        if (s.message != null &&
            s.phase != ScreenGuidePhase.privacyPaused &&
            s.phase != ScreenGuidePhase.needsAccessibility)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(s.message!, key: const Key('screenGuideMessage')),
          ),
        if (!running &&
            s.phase != ScreenGuidePhase.notIncluded &&
            s.phase != ScreenGuidePhase.disabled &&
            s.phase != ScreenGuidePhase.unavailable) ...[
          TextField(
            key: const Key('screenGuideGoal'),
            controller: _goal,
            maxLength: 200,
            decoration: InputDecoration(
                labelText: t('What do you want to do?', 'మీరు ఏమి చేయాలనుకుంటున్నారు?'),
                hintText: t('e.g. turn on Wi-Fi, book a bus ticket', 'ఉదా: వై-ఫై ఆన్ చేయడం')),
          ),
          FilledButton.icon(
            key: const Key('screenGuideStart'),
            onPressed: s.phase == ScreenGuidePhase.starting
                ? null
                : () async {
                    final language = Localizations.localeOf(context).toLanguageTag();
                    if (!await screenGuideConsented()) {
                      if (!context.mounted || !await showScreenGuideDisclosure(context)) return;
                    }
                    await c.start(_goal.text, language: language);
                  },
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(t('Start guide', 'గైడ్ ప్రారంభించండి')),
          ),
        ] else
          Wrap(spacing: 8, children: [
            FilledButton(
              key: const Key('screenGuideContinue'),
              onPressed: c.resume,
              child: Text(t('Continue', 'కొనసాగించండి')),
            ),
            OutlinedButton(
              key: const Key('screenGuideEnd'),
              onPressed: () => c.end(),
              child: Text(t('End Guide', 'గైడ్ ముగించండి')),
            ),
          ]),
      ]),
    );
  }
}
