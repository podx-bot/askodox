import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/backend_providers.dart';
import '../data/business_center_repository.dart';

/// Business Command Center for a seller / provider: their own counted facts
/// and what to do next (same records staff see). Each insight says whether
/// it is a confirmed fact, a possible cause or a recommendation.
/// The My Business sections (Analytics is the counted summary + insights on
/// this screen itself). Order follows the approved navigation.
List<({String id, String label, IconData icon, String route})> askodoxBusinessSections(bool te) {
  String t(String en, String tel) => te ? tel : en;
  return [
    (id: 'profile', label: t('Business profile', 'వ్యాపార ప్రొఫైల్'), icon: Icons.store_mall_directory_outlined,
        route: '/profile'),
    (id: 'listings', label: t('My listings', 'నా లిస్టింగ్‌లు'), icon: Icons.inventory_2_outlined,
        route: '/listings/mine'),
    (id: 'promotions', label: t('Promotions & coupons', 'ప్రమోషన్లు & కూపన్లు'), icon: Icons.local_offer_outlined,
        route: '/business/promotions'),
    (id: 'automation', label: t('Conversations & automation', 'సంభాషణలు & ఆటోమేషన్'),
        icon: Icons.smart_toy_outlined, route: '/business/automation'),
    (id: 'orders', label: t('Business orders', 'వ్యాపార ఆర్డర్లు'), icon: Icons.receipt_long_outlined,
        route: '/orders/incoming'),
    (id: 'settings', label: t('Business settings', 'వ్యాపార సెట్టింగ్‌లు'), icon: Icons.tune_rounded,
        route: '/business/automation?section=settings'),
  ];
}

class BusinessCenterScreen extends ConsumerWidget {
  const BusinessCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = Localizations.localeOf(context).languageCode;
    final te = language == 'te';
    String t(String en, String tel) => te ? tel : en;
    final signedIn = ref.watch(authSessionProvider).user != null;
    final data = ref.watch(businessCenterProvider(language));
    return Scaffold(
      appBar: AppBar(title: Text(t('My business', 'నా వ్యాపారం'))),
      body: !signedIn
          ? Center(child: Text(t('Sign in to see your business.', 'సైన్ ఇన్ చేయండి.')))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(businessCenterProvider(language)),
              child: data.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => ListView(children: [
                  ListTile(
                    key: const Key('askodoxBusinessError'),
                    title: Text(t('Could not load your business summary.', 'వ్యాపార సారాంశం లోడ్ కాలేదు.')),
                    trailing: TextButton(
                      onPressed: () => ref.invalidate(businessCenterProvider(language)),
                      child: Text(t('Retry', 'మళ్లీ ప్రయత్నించండి')),
                    ),
                  ),
                ]),
                data: (page) => ListView(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      _Stat(t('Listings', 'లిస్టింగ్‌లు'), page.summary['listings'], '/listings/mine'),
                      _Stat(t('Waiting requests', 'ఎదురుచూస్తున్నవి'), page.summary['requests_waiting'], '/orders/incoming'),
                      _Stat(t('In progress', 'జరుగుతున్నవి'), page.summary['in_progress'], '/orders/incoming'),
                      _Stat(t('Completed', 'పూర్తయినవి'), page.summary['completed'], '/orders/incoming'),
                      _Stat(t('New demand', 'కొత్త డిమాండ్'), page.summary['opportunities_new'], '/opportunities'),
                    ]),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 4),
                      child: Text(t('Analytics', 'విశ్లేషణ'),
                          key: const Key('askodoxBusinessSection-analytics'),
                          style: Theme.of(context).textTheme.titleSmall),
                    ),
                    for (final i in page.insights) _InsightCard(insight: i),
                    if (page.basis.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(page.basis, style: Theme.of(context).textTheme.bodySmall),
                      ),
                    const SizedBox(height: 12),
                    // My Business sections: each opens its one real screen.
                    for (final section in askodoxBusinessSections(te))
                      Card(
                        elevation: 0,
                        child: ListTile(
                          key: ValueKey('askodoxBusinessSection-${section.id}'),
                          leading: Icon(section.icon),
                          title: Text(section.label),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => section.route.startsWith('/profile')
                              ? context.go(section.route)
                              : context.push(section.route),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// A counted fact that opens the screen behind it (never a dead tile).
class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.route);

  final String label;
  final int? value;
  final String route;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        key: Key('askodoxBusinessStat-$route-$label'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${value ?? 0}', style: Theme.of(context).textTheme.titleMedium),
              Text(label, style: Theme.of(context).textTheme.bodySmall),
            ]),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 18),
          ]),
        ),
      ),
    );
  }
}

Color askodoxSeverityColor(String severity) => switch (severity) {
      'red' => const Color(0xFFD32F2F),
      'green' => const Color(0xFF2E7D32),
      _ => const Color(0xFFEF6C00),
    };

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final BusinessInsight insight;

  @override
  Widget build(BuildContext context) {
    final color = askodoxSeverityColor(insight.severity);
    final route = insight.actionRoute;
    return Card(
      key: Key('askodoxBusinessInsight-${insight.kind}-${insight.severity}'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: .5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.circle, size: 10, color: color),
            const SizedBox(width: 6),
            Text(insight.label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
          ]),
          const SizedBox(height: 4),
          Text(insight.title, style: Theme.of(context).textTheme.titleSmall),
          if (insight.detail.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text(insight.detail)),
          if (route != null && route.isNotEmpty && (insight.actionLabel ?? '').isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: Key('askodoxBusinessAction-$route'),
                onPressed: () => context.push(route),
                child: Text(insight.actionLabel!),
              ),
            ),
        ]),
      ),
    );
  }
}
