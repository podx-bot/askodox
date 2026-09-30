import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/providers/backend_providers.dart';
import '../application/askodox_notifications.dart';
import '../data/promotions_repository.dart';

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
          if (signedIn) const AskodoxPromotionsSection(),
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

/// "Offers for you": reviewed promotions delivered to this customer (at
/// most five, compact / quarter / half card, "Sponsored" when paid). Hidden
/// when there are none; each can be dismissed.
class AskodoxPromotionsSection extends ConsumerWidget {
  const AskodoxPromotionsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final promos = ref.watch(askodoxPromotionsProvider).valueOrNull ?? const <AskodoxPromotion>[];
    if (promos.isEmpty) return const SizedBox.shrink();
    final repo = ref.read(promotionsRepositoryProvider);
    return Column(
      key: const Key('askodoxPromotions'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(te ? 'మీ కోసం ఆఫర్లు' : 'Offers for you',
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ),
        for (final promo in promos)
          _PromotionCard(
            key: ValueKey('askodoxPromo-${promo.deliveryId}'),
            promo: promo,
            te: te,
            onShown: () => repo.track(promo.deliveryId, 'open'),
            onOpen: () async {
              await repo.track(promo.deliveryId, 'click');
              final link = promo.deepLink;
              if (link == null || !context.mounted) return;
              if (link.startsWith('/')) {
                context.push(link);
              } else if (Uri.tryParse(link) case final uri?) {
                try {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                } catch (_) {}
              }
            },
            onDismiss: () async {
              await repo.track(promo.deliveryId, 'dismiss');
              ref.invalidate(askodoxPromotionsProvider);
            },
          ),
      ],
    );
  }
}

class _PromotionCard extends StatefulWidget {
  const _PromotionCard({
    super.key,
    required this.promo,
    required this.te,
    required this.onShown,
    required this.onOpen,
    required this.onDismiss,
  });

  final AskodoxPromotion promo;
  final bool te;
  final VoidCallback onShown;
  final Future<void> Function() onOpen;
  final Future<void> Function() onDismiss;

  @override
  State<_PromotionCard> createState() => _PromotionCardState();
}

class _PromotionCardState extends State<_PromotionCard> {
  @override
  void initState() {
    super.initState();
    widget.onShown();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.promo;
    final imageHeight = switch (p.size) { 'half' => 150.0, 'quarter' => 84.0, _ => 0.0 };
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (imageHeight > 0 && p.imageUrl != null)
          SizedBox(
            height: imageHeight,
            width: double.infinity,
            child: Image.network(p.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox()),
          ),
        ListTile(
          dense: p.size == 'compact',
          leading: p.size == 'compact' ? const Icon(Icons.local_offer_outlined) : null,
          title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.body, maxLines: p.size == 'half' ? 4 : 2, overflow: TextOverflow.ellipsis),
            if (p.disclosure != null)
              Text(
                  [widget.te ? 'ప్రాయోజిత' : p.disclosure!, if (p.advertiser != null) p.advertiser!].join(' · '),
                  key: const Key('askodoxPromoDisclosure'),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
          ]),
          trailing: IconButton(
            tooltip: widget.te ? 'తీసివేయి' : 'Dismiss',
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: widget.onDismiss,
          ),
        ),
        if (p.ctaLabel != null && p.deepLink != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: FilledButton.tonal(onPressed: widget.onOpen, child: Text(p.ctaLabel!)),
          ),
      ]),
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
