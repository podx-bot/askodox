import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/backend_providers.dart';
import '../application/askodox_notifications.dart';

/// "Updates": the ONE place for what happened to the user's requests --
/// requests they sent, requests sent to them, and customer leads. Real
/// data only (no demo shops or sample notifications).
class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final signedIn = ref.watch(authSessionProvider).user != null;
    final updates = ref.watch(askodoxUpdatesProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(askodoxUpdatesProvider),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(children: [
            Expanded(
              child: Text(t('Updates', 'అప్‌డేట్స్'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            ),
            IconButton(
              key: const Key('askodoxNotificationSettings'),
              tooltip: t('Notifications', 'నోటిఫికేషన్స్'),
              onPressed: () => context.push('/settings/notifications'),
              icon: const Icon(Icons.notifications_none_rounded),
            ),
          ]),
          const AskodoxNotificationsOffBanner(),
          if (!signedIn)
            Card(
              key: const Key('askodoxUpdatesSignIn'),
              child: ListTile(
                leading: const Icon(Icons.phone_iphone_rounded),
                title: Text(t('Sign in to see your requests', 'మీ అభ్యర్థనలు చూడడానికి సైన్ ఇన్ చేయండి')),
                subtitle: Text(t('Searching and browsing never need sign-in.', 'వెతకడానికి సైన్ ఇన్ అవసరం లేదు.')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push('/onboarding?signin=1'),
              ),
            )
          else
            updates.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => ListTile(
                title: Text(t('Could not load updates.', 'అప్‌డేట్స్ లోడ్ కాలేదు.')),
                trailing: TextButton(
                  onPressed: () => ref.invalidate(askodoxUpdatesProvider),
                  child: Text(t('Retry', 'మళ్లీ ప్రయత్నించండి')),
                ),
              ),
              data: (items) => items.isEmpty
                  ? Padding(
                      key: const Key('askodoxUpdatesEmpty'),
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Text(
                        t('No updates yet. When you send a request, its status shows here.',
                            'ఇంకా అప్‌డేట్స్ లేవు. మీరు అభ్యర్థన పంపినప్పుడు దాని స్థితి ఇక్కడ కనిపిస్తుంది.'),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : Column(children: [
                      for (final item in items)
                        Card(
                          key: ValueKey('askodoxUpdate-${item.key}'),
                          child: ListTile(
                            leading: Icon(switch (item.kind) {
                              AskodoxUpdateKind.requests => Icons.shopping_bag_outlined,
                              AskodoxUpdateKind.replies => Icons.storefront_outlined,
                              AskodoxUpdateKind.leads => Icons.campaign_outlined,
                            }),
                            title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text(item.status),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => item.route == '/' ? context.go('/') : context.push(item.route),
                          ),
                        ),
                    ]),
            ),
        ],
      ),
    );
  }
}

/// Shown only when Android notifications are OFF for ASKODOX: ASKODOX can
/// not switch them on itself, so it opens the right Android settings page.
class AskodoxNotificationsOffBanner extends ConsumerStatefulWidget {
  const AskodoxNotificationsOffBanner({super.key});

  @override
  ConsumerState<AskodoxNotificationsOffBanner> createState() => _AskodoxNotificationsOffBannerState();
}

class _AskodoxNotificationsOffBannerState extends ConsumerState<AskodoxNotificationsOffBanner>
    with WidgetsBindingObserver {
  bool? _systemOn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh(); // back from Android settings
  }

  Future<void> _refresh() async {
    final on = await ref.read(askodoxDeviceNotificationsProvider).enabledInSystem();
    if (mounted) setState(() => _systemOn = on);
  }

  Future<void> _enable() async {
    final device = ref.read(askodoxDeviceNotificationsProvider);
    final granted = await device.requestPermission();
    if (granted != true) await device.openSystemSettings();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_systemOn != false) return const SizedBox.shrink();
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Card(
      key: const Key('askodoxNotificationsOff'),
      color: const Color(0xFFFFF4E5),
      child: ListTile(
        leading: const Icon(Icons.notifications_off_outlined),
        title: Text(te ? 'నోటిఫికేషన్స్ ఆఫ్‌లో ఉన్నాయి' : 'Notifications are off'),
        trailing: FilledButton(
          key: const Key('askodoxEnableNotifications'),
          onPressed: _enable,
          child: Text(te ? 'ఆన్ చేయండి' : 'Enable'),
        ),
      ),
    );
  }
}
