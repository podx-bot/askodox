import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        ],
      ),
    );
  }
}
