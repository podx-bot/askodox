import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/backend_providers.dart';
import '../data/pos_payment_alerts.dart';

/// Why this phone would stay silent for a payment (owner 2026-11-16: the app must SAY it, not stay quiet).
enum AskodoxAlertHealth { unknown, ok, off, needsAccess, noListener, noApps, noVoice }

/// Pure decision (unit tested): [status] is the native status map, [mineEnabled] / [mineApps] the "My phone" switch
/// and its app list. A phone that listens for a shop (status `enabled`) counts as on.
AskodoxAlertHealth askodoxAlertHealthOf(Map<String, Object?> status, {required bool mineEnabled, required int mineApps}) {
  if (status['unavailable'] == true || status['error'] != null) return AskodoxAlertHealth.unknown; // not a phone
  final shopOn = status['enabled'] == true;
  if (!mineEnabled && !shopOn) return AskodoxAlertHealth.off;
  if (status['listenerDeclared'] != true) return AskodoxAlertHealth.noListener;
  if (status['listenerAllowed'] != true) return AskodoxAlertHealth.needsAccess;
  if (mineEnabled && !shopOn && mineApps == 0) return AskodoxAlertHealth.noApps;
  if (status['ttsReady'] == false || status['ttsLanguageOk'] == false) return AskodoxAlertHealth.noVoice;
  return AskodoxAlertHealth.ok;
}

/// How long a dismissed warning stays hidden: the "never turned on" nudge is quiet for a week, a broken setup
/// (switched on but one part missing) comes back after a day.
Duration askodoxAlertSnooze(AskodoxAlertHealth h) => h == AskodoxAlertHealth.off ? const Duration(days: 7) : const Duration(days: 1);

String askodoxAlertHealthText(AskodoxAlertHealth h, bool te) => switch (h) {
      AskodoxAlertHealth.off => te
          ? 'ఈ ఫోన్ లో పేమెంట్ శబ్దం ఆఫ్ లో ఉంది. ఒక్క నొక్కుతో ఆన్ చేయండి.'
          : 'Payment voice is off on this phone. Turn it on in one tap.',
      AskodoxAlertHealth.needsAccess => te
          ? 'పేమెంట్ శబ్దం రావడానికి నోటిఫికేషన్ యాక్సెస్ ఇవ్వాలి. ఇప్పుడు ఇవ్వండి.'
          : 'Payment voice needs notification access. Allow it now.',
      AskodoxAlertHealth.noListener => te
          ? 'ఈ యాప్ వెర్షన్ నోటిఫికేషన్లు చదవలేదు. Play Store నుంచి అప్‌డేట్ చేయండి.'
          : 'This app version cannot read payment notifications. Update it from Play Store.',
      AskodoxAlertHealth.noApps => te
          ? 'చదవడానికి ఏ పేమెంట్ / SMS యాప్ ఎంచుకోలేదు. ఎంచుకోండి.'
          : 'No payment / SMS app is chosen to listen to. Choose them.',
      AskodoxAlertHealth.noVoice => te
          ? 'ఈ ఫోన్ లో మాట్లాడే వాయిస్ (Text-to-speech) సిద్ధంగా లేదు. సరిచేయండి.'
          : 'The phone voice (text-to-speech) is not ready. Fix it.',
      _ => '',
    };

const _snoozeKey = 'askodox.payalert.banner.snooze.v1';

/// What the phone says about its own payment alerts. Also hands the native listener the CURRENT settings (token,
/// server address) at every app start, so a phone that set "My phone" up once keeps working without opening the page.
final askodoxPaymentAlertHealthProvider = FutureProvider.autoDispose<AskodoxAlertHealth>((ref) async {
  final bridge = ref.read(askodoxPaymentAlertsBridgeProvider);
  final mine = await AskodoxMyPhoneAlerts.load();
  if (mine.setupDone) {
    try {
      var base = '';
      var token = '';
      try {
        base = ref.read(appConfigProvider).apiBaseUrl?.toString() ?? '';
        final session = ref.read(authSessionProvider);
        token = session.user == null ? '' : (session.tokenPlaceholder ?? '');
      } catch (_) {}
      await bridge.configurePersonal(mine.nativeConfig(baseUrl: base, token: token));
    } catch (_) {}
  }
  final status = await bridge.status();
  return askodoxAlertHealthOf(status, mineEnabled: mine.enabled, mineApps: mine.apps.length);
});

/// One red / amber strip at the top of Home: says what is missing and opens the ONE page that fixes it.
class AskodoxPaymentAlertBanner extends ConsumerStatefulWidget {
  const AskodoxPaymentAlertBanner({super.key});

  @override
  ConsumerState<AskodoxPaymentAlertBanner> createState() => _AskodoxPaymentAlertBannerState();
}

class _AskodoxPaymentAlertBannerState extends ConsumerState<AskodoxPaymentAlertBanner> {
  bool _hidden = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final until = prefs.getInt(_snoozeKey) ?? 0;
      if (mounted) setState(() => _hidden = DateTime.now().millisecondsSinceEpoch < until);
    } catch (_) {}
    if (mounted) setState(() => _checked = true);
  }

  Future<void> _dismiss(AskodoxAlertHealth h) async {
    setState(() => _hidden = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_snoozeKey, DateTime.now().add(askodoxAlertSnooze(h)).millisecondsSinceEpoch);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || _hidden) return const SizedBox.shrink();
    final signedIn = ref.watch(authSessionProvider).user != null;
    if (!signedIn) return const SizedBox.shrink();
    final health = ref.watch(askodoxPaymentAlertHealthProvider).valueOrNull ?? AskodoxAlertHealth.unknown;
    if (health == AskodoxAlertHealth.ok || health == AskodoxAlertHealth.unknown) return const SizedBox.shrink();
    final te = Localizations.localeOf(context).languageCode == 'te';
    final broken = health != AskodoxAlertHealth.off;
    return Material(
      key: const Key('askodoxPaymentAlertBanner'),
      color: broken ? const Color(0xFFFEE2E2) : const Color(0xFFFEF3C7),
      child: InkWell(
        onTap: () => context.push('/me/payments/phone'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(children: [
            Icon(broken ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                color: broken ? const Color(0xFFB91C1C) : const Color(0xFFB45309), size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Text(askodoxAlertHealthText(health, te),
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF1F2937)))),
            TextButton(
                key: const Key('askodoxPaymentAlertBannerFix'),
                onPressed: () => context.push('/me/payments/phone'),
                child: Text(te ? 'సరిచేయి' : 'Fix')),
            IconButton(
                key: const Key('askodoxPaymentAlertBannerClose'),
                tooltip: te ? 'తర్వాత' : 'Later',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => _dismiss(health)),
          ]),
        ),
      ),
    );
  }
}
