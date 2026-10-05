import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/backend_providers.dart';
import '../data/business_center_repository.dart';

/// Business Command Center for a seller / provider: their own counted facts
/// and what to do next (same records staff see). Each insight says whether
/// it is a confirmed fact, a possible cause or a recommendation.
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
                      _Stat(t('Listings', 'లిస్టింగ్‌లు'), page.summary['listings']),
                      _Stat(t('Waiting requests', 'ఎదురుచూస్తున్నవి'), page.summary['requests_waiting']),
                      _Stat(t('In progress', 'జరుగుతున్నవి'), page.summary['in_progress']),
                      _Stat(t('Completed', 'పూర్తయినవి'), page.summary['completed']),
                      _Stat(t('New demand', 'కొత్త డిమాండ్'), page.summary['opportunities_new']),
                    ]),
                    const SizedBox(height: 12),
                    for (final i in page.insights) _InsightCard(insight: i),
                    if (page.basis.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(page.basis, style: Theme.of(context).textTheme.bodySmall),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final int? value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${value ?? 0}', style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]),
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
