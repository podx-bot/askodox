import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../../services/in_app_messaging.dart';
import '../../../services/push_registration.dart';
import '../application/askodox_notifications.dart';
import 'updates_screen.dart';

/// Notifications: one switch. Routine updates are silent by default; the
/// per-kind choices stay hidden under "Choose what I receive".
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final settings = ref.watch(askodoxNotificationSettingsProvider);
    final controller = ref.read(askodoxNotificationSettingsProvider.notifier);
    String kindLabel(AskodoxUpdateKind kind) => switch (kind) {
          AskodoxUpdateKind.requests => t('My requests (seller replies, status)', 'నా అభ్యర్థనలు (విక్రేత సమాధానం, స్థితి)'),
          AskodoxUpdateKind.replies => t('Requests sent to me', 'నాకు వచ్చిన అభ్యర్థనలు'),
          AskodoxUpdateKind.leads => t('Customers looking for my service', 'నా సేవ కోసం వెతుకుతున్న కస్టమర్లు'),
          AskodoxUpdateKind.opportunities =>
            t('Demand matched to my listings', 'నా లిస్టింగ్‌లకు సరిపోయే డిమాండ్'),
          AskodoxUpdateKind.notices => t('ASKODOX notices', 'ASKODOX సమాచారం'),
        };
    return Scaffold(
      appBar: AppBar(title: Text(t('Notifications', 'నోటిఫికేషన్స్'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const AskodoxNotificationsOffBanner(),
          SwitchListTile(
            key: const Key('askodoxNotificationsSwitch'),
            title: Text(t('Notifications', 'నోటిఫికేషన్స్'), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(settings.enabled ? t('On', 'ఆన్') : t('Off', 'ఆఫ్')),
            secondary: IconButton(
              key: const Key('askodoxNotificationsInfo'),
              icon: const Icon(Icons.info_outline_rounded),
              tooltip: t('What is this?', 'ఇది ఏమిటి?'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  content: Text(t(
                    'ASKODOX tells you when a seller replies or your request changes. These arrive silently -- no sound or vibration.',
                    'విక్రేత సమాధానం ఇచ్చినప్పుడు లేదా మీ అభ్యర్థన మారినప్పుడు ASKODOX తెలియజేస్తుంది. ఇవి శబ్దం లేకుండా వస్తాయి.',
                  )),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
                ),
              ),
            ),
            value: settings.enabled,
            onChanged: controller.setEnabled,
          ),
          if (settings.enabled)
            ExpansionTile(
              key: const Key('askodoxChooseNotifications'),
              title: Text(t('Choose what I receive', 'ఏవి రావాలో ఎంచుకోండి')),
              children: [
                for (final kind in AskodoxUpdateKind.values)
                  SwitchListTile(
                    key: ValueKey('askodoxNotify-${kind.name}'),
                    title: Text(kindLabel(kind)),
                    value: settings.allows(kind),
                    onChanged: (on) => controller.setKind(kind, on),
                  ),
              ],
            ),
          const Divider(height: 24),
          const AskodoxInAppOffersSwitch(),
          if (ref.watch(authSessionProvider).user != null) const AskodoxPushSelfTest(),
        ],
      ),
    );
  }
}

/// Opt-in for Firebase In-App Messaging (off until switched on).
class AskodoxInAppOffersSwitch extends ConsumerStatefulWidget {
  const AskodoxInAppOffersSwitch({super.key});

  @override
  ConsumerState<AskodoxInAppOffersSwitch> createState() => _AskodoxInAppOffersSwitchState();
}

class _AskodoxInAppOffersSwitchState extends ConsumerState<AskodoxInAppOffersSwitch> {
  bool? _on;

  @override
  void initState() {
    super.initState();
    ref.read(askodoxInAppMessagingProvider).optedIn().then((on) {
      if (mounted) setState(() => _on = on);
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final messaging = ref.watch(askodoxInAppMessagingProvider);
    return SwitchListTile(
      key: const Key('askodoxInAppOffersSwitch'),
      title: Text(t('Offer messages in the app', 'యాప్‌లో ఆఫర్ సందేశాలు'), style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(messaging.configured
          ? t('At most one a day, only while you use ASKODOX. Off = none, and nothing is collected for them.',
              'రోజుకు గరిష్టంగా ఒకటి, మీరు ASKODOX వాడుతున్నప్పుడే. ఆఫ్ = ఏవీ రావు, వాటి కోసం ఏదీ సేకరించబడదు.')
          : t('Not available in this app build.', 'ఈ యాప్ బిల్డ్‌లో అందుబాటులో లేదు.')),
      value: _on ?? false,
      onChanged: !messaging.configured || _on == null
          ? null
          : (on) async {
              setState(() => _on = on);
              await messaging.setOptIn(on);
            },
    );
  }
}

/// One test notification to THIS person's own phones (server-side, at most
/// three per ten minutes). Says honestly when push is not set up yet.
class AskodoxPushSelfTest extends ConsumerStatefulWidget {
  const AskodoxPushSelfTest({super.key});

  @override
  ConsumerState<AskodoxPushSelfTest> createState() => _AskodoxPushSelfTestState();
}

class _AskodoxPushSelfTestState extends ConsumerState<AskodoxPushSelfTest> {
  bool _busy = false;
  String? _result;

  Future<void> _send(bool te) async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final push = ref.read(askodoxPushRegistrationProvider);
    final state = await push.sync();
    final token = ref.read(authSessionProvider).tokenPlaceholder;
    final result = await ref.read(apiClientProvider).post<Map<String, Object?>>('/api/me/push-test',
        options: ApiRequestOptions(authToken: token));
    if (!mounted) return;
    String text;
    if (state == AskodoxPushState.notConfigured) {
      text = te ? 'ఈ యాప్ బిల్డ్‌లో పుష్ సెటప్ కాలేదు (Firebase విలువలు లేవు).' : 'Push is not set up in this app build (no Firebase values).';
    } else if (state == AskodoxPushState.permissionDenied) {
      text = te
          ? 'నోటిఫికేషన్ అనుమతి ఆఫ్‌లో ఉంది. Android సెట్టింగ్స్ -> యాప్స్ -> ASKODOX -> నోటిఫికేషన్స్.'
          : 'Notification permission is off. Android Settings -> Apps -> ASKODOX -> Notifications.';
    } else if (result is ApiSuccess<Map<String, Object?>>) {
      text = '${result.data['status']}: ${result.data['detail']}';
    } else if (result is ApiError<Map<String, Object?>>) {
      text = result.failure.message ?? result.failure.localizedMessage(te ? 'te' : 'en');
    } else {
      text = '';
    }
    setState(() {
      _busy = false;
      _result = text;
    });
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    return ListTile(
      key: const Key('askodoxPushSelfTest'),
      leading: const Icon(Icons.notifications_active_outlined),
      title: Text(te ? 'ఈ ఫోన్‌కు టెస్ట్ నోటిఫికేషన్ పంపండి' : 'Send a test notification to this phone'),
      subtitle: _result == null ? null : Text(_result!, key: const Key('askodoxPushSelfTestResult')),
      trailing: _busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.send_rounded),
      onTap: _busy ? null : () => _send(te),
    );
  }
}
