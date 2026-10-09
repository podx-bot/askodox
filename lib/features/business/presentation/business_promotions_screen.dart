import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// My Business -> Promotions & Coupons: the seller's own offers
/// (/api/merchant/offers). Every new offer is reviewed by ASKODOX before
/// customers see it; the seller can pause, resume or archive.
final _offersProvider = FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session.user == null) return const [];
  final result = await ref
      .watch(apiClientProvider)
      .get<Map<String, Object?>>('/api/merchant/offers', options: ApiRequestOptions(authToken: session.tokenPlaceholder));
  if (result is! ApiSuccess<Map<String, Object?>>) throw StateError('offers unavailable');
  return [for (final row in (result.data['items'] as List?) ?? const []) if (row is Map) Map<String, Object?>.from(row)];
});

class BusinessPromotionsScreen extends ConsumerWidget {
  const BusinessPromotionsScreen({super.key});

  static const kinds = ['flat', 'percent', 'cashback', 'free_delivery', 'free_item', 'bogo', 'special_price', 'custom'];

  static String statusLabel(String status, bool te) => switch (status.toUpperCase()) {
        'PENDING_REVIEW' => te ? 'ASKODOX రివ్యూలో ఉంది' : 'Waiting for ASKODOX review',
        'ACTIVE' || 'LIVE' || 'APPROVED' => te ? 'కస్టమర్లకు కనిపిస్తుంది' : 'Live for customers',
        'PAUSED' => te ? 'ఆపివేయబడింది' : 'Paused',
        'REJECTED' => te ? 'తిరస్కరించబడింది' : 'Not approved',
        'EXPIRED' => te ? 'గడువు ముగిసింది' : 'Expired',
        _ => status,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final offers = ref.watch(_offersProvider);
    final session = ref.watch(authSessionProvider);
    final client = ref.read(apiClientProvider);
    final auth = ApiRequestOptions(authToken: session.tokenPlaceholder);
    void say(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    Future<void> action(String id, String verb) async {
      final r = await client.post<Map<String, Object?>>('/api/merchant/offers/$id/$verb', options: auth);
      ref.invalidate(_offersProvider);
      if (r is! ApiSuccess && context.mounted) say(t('Could not update the offer.', 'ఆఫర్ మార్చలేకపోయాం.'));
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('Promotions & coupons', 'ప్రమోషన్లు & కూపన్లు'))),
      floatingActionButton: session.user == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('askodoxOfferCreate'),
              icon: const Icon(Icons.add),
              label: Text(t('New offer', 'కొత్త ఆఫర్')),
              onPressed: () async {
                final data = await showModalBottomSheet<Map<String, Object?>>(
                    context: context, isScrollControlled: true, builder: (_) => _OfferForm(te: te));
                if (data == null) return;
                final r = await client.post<Map<String, Object?>>('/api/merchant/offers', body: {'data': data}, options: auth);
                ref.invalidate(_offersProvider);
                if (!context.mounted) return;
                if (r case ApiError(:final failure)) {
                  say(failure.statusCode == 409
                      ? t('Merchant offers are not open yet.', 'మర్చంట్ ఆఫర్లు ఇంకా తెరవలేదు.')
                      : t('Could not save the offer.', 'ఆఫర్ సేవ్ కాలేదు.'));
                } else {
                  say(t('Sent for ASKODOX review -- customers see it after approval.',
                      'ASKODOX రివ్యూకి పంపాం -- ఆమోదం తర్వాత కస్టమర్లకు కనిపిస్తుంది.'));
                }
              },
            ),
      body: session.user == null
          ? Center(child: Text(t('Sign in to manage offers.', 'సైన్ ఇన్ చేయండి.')))
          : offers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () => ref.invalidate(_offersProvider),
                      child: Text(t('Could not load. Retry', 'లోడ్ కాలేదు. మళ్లీ')))),
              data: (items) => ListView(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 96 + MediaQuery.paddingOf(context).bottom),
                children: [
                  if (items.isEmpty)
                    Padding(
                      key: const Key('askodoxOffersEmpty'),
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(t('No offers yet. Create one -- ASKODOX reviews it before customers see it.',
                          'ఇంకా ఆఫర్లు లేవు. ఒకటి సృష్టించండి -- కస్టమర్లకు చూపించే ముందు ASKODOX రివ్యూ చేస్తుంది.')),
                    ),
                  for (final offer in items)
                    Card(
                      key: ValueKey('askodoxOffer-${offer['id']}'),
                      child: ListTile(
                        title: Text('${(offer['data'] as Map?)?['title'] ?? offer['title'] ?? ''}'),
                        subtitle: Text(statusLabel('${offer['status'] ?? ''}', te)),
                        trailing: PopupMenuButton<String>(
                          onSelected: (verb) => action('${offer['id']}', verb),
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'pause', child: Text(t('Pause', 'ఆపు'))),
                            PopupMenuItem(value: 'resume', child: Text(t('Resume', 'మళ్లీ ప్రారంభించు'))),
                            PopupMenuItem(value: 'archive', child: Text(t('Archive', 'ఆర్కైవ్'))),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _OfferForm extends StatefulWidget {
  const _OfferForm({required this.te});
  final bool te;

  @override
  State<_OfferForm> createState() => _OfferFormState();
}

class _OfferFormState extends State<_OfferForm> {
  final _title = TextEditingController();
  final _value = TextEditingController();
  final _description = TextEditingController();
  String _kind = 'percent';

  @override
  Widget build(BuildContext context) {
    String t(String en, String tel) => widget.te ? tel : en;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
            key: const Key('askodoxOfferTitle'),
            controller: _title,
            decoration: InputDecoration(labelText: t('Offer title', 'ఆఫర్ పేరు'))),
        DropdownButtonFormField<String>(
          initialValue: _kind,
          decoration: InputDecoration(labelText: t('Offer type', 'ఆఫర్ రకం')),
          items: [for (final k in BusinessPromotionsScreen.kinds) DropdownMenuItem(value: k, child: Text(k))],
          onChanged: (v) => setState(() => _kind = v ?? _kind),
        ),
        TextField(
            key: const Key('askodoxOfferValue'),
            controller: _value,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: t('Value (₹ or %)', 'విలువ (₹ లేదా %)'))),
        TextField(
            controller: _description,
            decoration: InputDecoration(labelText: t('Description / terms', 'వివరణ / షరతులు'))),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('askodoxOfferSubmit'),
          onPressed: () {
            if (_title.text.trim().isEmpty) return;
            Navigator.pop(context, <String, Object?>{
              'title': _title.text.trim(),
              'offer_kind': _kind,
              if (num.tryParse(_value.text.trim()) case final v?) 'value': v,
              if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
            });
          },
          child: Text(t('Send for review', 'రివ్యూకి పంపు')),
        ),
      ]),
    );
  }
}
