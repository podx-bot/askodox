import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/backend_providers.dart';
import '../data/opportunities_repository.dart';

/// Seller Opportunities: customer demand matched to what this seller /
/// provider offers. Accept (I can serve this) or decline (with a reason),
/// see expiry and status. Customers' identities are never shown.
class SellerOpportunitiesScreen extends ConsumerWidget {
  const SellerOpportunitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = Localizations.localeOf(context).languageCode;
    final te = language == 'te';
    String t(String en, String tel) => te ? tel : en;
    final signedIn = ref.watch(authSessionProvider).user != null;
    final data = ref.watch(sellerOpportunitiesProvider(language));
    return Scaffold(
      appBar: AppBar(title: Text(t('Customer demand for you', 'మీ కోసం కస్టమర్ డిమాండ్'))),
      body: !signedIn
          ? Center(child: Text(t('Sign in to see demand for your listings.', 'సైన్ ఇన్ చేయండి.')))
          : RefreshIndicator(
              onRefresh: () async => ref.invalidate(sellerOpportunitiesProvider(language)),
              child: data.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => ListView(children: [
                  ListTile(
                    title: Text(t('Could not load opportunities.', 'అవకాశాలు లోడ్ కాలేదు.')),
                    trailing: TextButton(
                      onPressed: () => ref.invalidate(sellerOpportunitiesProvider(language)),
                      child: Text(t('Retry', 'మళ్లీ ప్రయత్నించండి')),
                    ),
                  ),
                ]),
                data: (page) => ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (page.privacy.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.lock_outline_rounded, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(page.privacy, style: Theme.of(context).textTheme.bodySmall)),
                        ]),
                      ),
                    if (page.items.isEmpty)
                      Card(
                        key: const Key('askodoxOpportunitiesEmpty'),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            t('No customer demand matched to your listings yet. When people nearby look for what you offer, it appears here.',
                                'మీ లిస్టింగ్‌లకు ఇంకా డిమాండ్ లేదు. దగ్గరలో ఎవరైనా మీరు అందించేది వెతికితే ఇక్కడ కనిపిస్తుంది.'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    for (final item in page.items) _OpportunityCard(item: item, language: language),
                  ],
                ),
              ),
            ),
    );
  }
}

String askodoxOpportunityStatusWords(String status, {bool te = false}) => switch (status) {
      'new' => te ? 'కొత్తది' : 'New',
      'opened' => te ? 'చూశారు' : 'Seen',
      'accepted' => te ? 'అంగీకరించారు' : 'Accepted',
      'declined' => te ? 'తిరస్కరించారు' : 'Declined',
      'expired' => te ? 'గడువు ముగిసింది' : 'Expired',
      'fulfilled' => te ? 'పూర్తయింది' : 'Fulfilled',
      final other => other,
    };

class _OpportunityCard extends ConsumerStatefulWidget {
  const _OpportunityCard({required this.item, required this.language});

  final SellerOpportunity item;
  final String language;

  @override
  ConsumerState<_OpportunityCard> createState() => _OpportunityCardState();
}

class _OpportunityCardState extends ConsumerState<_OpportunityCard> {
  bool _busy = false;

  Future<void> _act(String action, {String reason = ''}) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(opportunitiesRepositoryProvider).act(widget.item.id, action, reason: reason);
      ref.invalidate(sellerOpportunitiesProvider(widget.language));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('$error'.replaceFirst('Bad state: ', ''))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    final te = widget.language == 'te';
    final reasons = te
        ? const ['స్టాక్ లేదు', 'ఈ ప్రాంతానికి సర్వీస్ లేదు', 'ధర సరిపోదు', 'ఇతర']
        : const ['Out of stock', 'Do not serve this area', 'Price does not fit', 'Other'];
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final r in reasons) ListTile(title: Text(r), onTap: () => Navigator.pop(context, r)),
        ]),
      ),
    );
    if (reason != null) await _act('decline', reason: reason);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final te = widget.language == 'te';
    String t(String en, String tel) => te ? tel : en;
    final expires = item.expiresAt?.toLocal();
    return Card(
      key: ValueKey('askodoxOpportunity-${item.id}'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(item.title.isEmpty ? item.subject : item.title,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            Chip(label: Text(askodoxOpportunityStatusWords(item.status, te: te))),
          ]),
          if (item.body.isNotEmpty) Text(item.body),
          const SizedBox(height: 6),
          Wrap(spacing: 12, runSpacing: 4, children: [
            if (item.category.isNotEmpty) Text('${t('Category', 'వర్గం')}: ${item.category}'),
            if (item.area.isNotEmpty) Text('${t('Area', 'ప్రాంతం')}: ${item.area}'),
            if (item.budgetBand != null) Text('${t('Budget', 'బడ్జెట్')}: ${item.budgetBand}'),
            if (expires != null && (item.canRespond || item.status == 'expired'))
              Text('${t('Expires', 'గడువు')}: ${expires.day}/${expires.month} '
                  '${expires.hour.toString().padLeft(2, '0')}:${expires.minute.toString().padLeft(2, '0')}'),
          ]),
          if (item.canRespond || item.canFulfil) const SizedBox(height: 10),
          if (item.canRespond)
            Row(children: [
              Expanded(
                child: FilledButton(
                  key: ValueKey('askodoxOpportunityAccept-${item.id}'),
                  onPressed: _busy ? null : () => _act('accept'),
                  child: Text(t('Accept', 'అంగీకరించు')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  key: ValueKey('askodoxOpportunityDecline-${item.id}'),
                  onPressed: _busy ? null : _decline,
                  child: Text(t('Decline', 'తిరస్కరించు')),
                ),
              ),
            ]),
          if (item.canFulfil)
            OutlinedButton.icon(
              key: ValueKey('askodoxOpportunityFulfil-${item.id}'),
              onPressed: _busy ? null : () => _act('fulfil'),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: Text(t('Mark fulfilled', 'పూర్తయినట్లు గుర్తించు')),
            ),
        ]),
      ),
    );
  }
}
