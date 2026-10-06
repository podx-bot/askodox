import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../home/application/conversation_archive.dart';

final _myListingsProvider = FutureProvider.autoDispose<List<Map<String, Object?>>>((ref) async {
  final session = ref.watch(authSessionProvider);
  if (session.user == null) return const [];
  final result = await ref.read(apiClientProvider).get<Map<String, Object?>>(
        '/api/products/mine',
        options: ApiRequestOptions(authToken: session.tokenPlaceholder),
      );
  if (result is! ApiSuccess<Map<String, Object?>>) throw StateError('unavailable');
  return [
    for (final item in (result.data['items'] as List? ?? const []))
      if (item is Map) Map<String, Object?>.from(item),
  ];
});

/// The seller's REAL listings (the ones buyers find in search), with
/// Edit (tap: price / size / stock) and Remove. New listings are made by telling ASKODOX ("I want to sell ...").
class MyListingsScreen extends ConsumerWidget {
  const MyListingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final listings = ref.watch(_myListingsProvider);

    Future<void> remove(Map<String, Object?> item) async {
      final session = ref.read(authSessionProvider);
      final result = await ref.read(apiClientProvider).delete<Map<String, Object?>>(
            '/api/products/mine/${item['id']}',
            options: ApiRequestOptions(authToken: session.tokenPlaceholder),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result is ApiSuccess
            ? t('Removed. Buyers will no longer see it.', 'తీసివేశాం. కొనుగోలుదారులకు ఇక కనిపించదు.')
            : t('Could not remove it right now.', 'ఇప్పుడు తీసివేయలేకపోయాం.')),
      ));
      ref.invalidate(_myListingsProvider);
    }

    Future<void> edit(Map<String, Object?> item) async {
      final price = TextEditingController(text: item['price'] == null ? '' : '${item['price']}');
      final variant = TextEditingController(text: '${item['variant'] ?? ''}');
      var stock = '${item['stock_status'] ?? 'UNKNOWN'}'.toUpperCase();
      final saved = await showModalBottomSheet<Map<String, Object?>>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => StatefulBuilder(
          builder: (sheet, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${item['subject'] ?? ''}', style: Theme.of(sheet).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                key: const Key('askodoxEditListingPrice'),
                controller: price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t('Price (₹)', 'ధర (₹)')),
              ),
              TextField(
                key: const Key('askodoxEditListingVariant'),
                controller: variant,
                decoration: InputDecoration(
                    labelText: t('Sizes / variant (e.g. Size: 8, 9, 10)', 'సైజులు / వేరియంట్ (ఉదా. Size: 8, 9, 10)')),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                key: const Key('askodoxEditListingStock'),
                segments: [
                  ButtonSegment(value: 'IN_STOCK', label: Text(t('In stock', 'స్టాక్ ఉంది'))),
                  ButtonSegment(value: 'OUT_OF_STOCK', label: Text(t('Out of stock', 'స్టాక్ లేదు'))),
                ],
                emptySelectionAllowed: true,
                selected: {if (stock != 'UNKNOWN') stock},
                onSelectionChanged: (v) => setSheet(() => stock = v.isEmpty ? 'UNKNOWN' : v.first),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('askodoxEditListingSave'),
                onPressed: () => Navigator.pop(sheet, <String, Object?>{
                  if (double.tryParse(price.text.trim()) != null) 'price': double.parse(price.text.trim()),
                  if (variant.text.trim().isNotEmpty) 'variant': variant.text.trim(),
                  'stock_status': stock,
                }),
                child: Text(t('Save', 'సేవ్ చేయండి')),
              ),
            ]),
          ),
        ),
      );
      if (saved == null || !context.mounted) return;
      final session = ref.read(authSessionProvider);
      final result = await ref.read(apiClientProvider).patch<Map<String, Object?>>(
            '/api/products/mine/${item['id']}',
            body: saved,
            options: ApiRequestOptions(authToken: session.tokenPlaceholder),
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        key: const Key('askodoxEditListingResult'),
        content: Text(result is ApiSuccess
            ? t('Saved. Buyers see the new details now.', 'సేవ్ అయింది. కొనుగోలుదారులకు కొత్త వివరాలు కనిపిస్తాయి.')
            : t('Could not save -- contact details and links are not allowed in a listing.',
                'సేవ్ కాలేదు -- లిస్టింగ్‌లో ఫోన్ నంబర్లు, లింకులు అనుమతించబడవు.')),
      ));
      ref.invalidate(_myListingsProvider);
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('My listings', 'నా లిస్టింగ్‌లు'))),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('askodoxAddListing'),
        onPressed: () {
          ref.read(askodoxChatRequestProvider.notifier).state =
              AskodoxChatRequest.ask(t('I want to sell', 'నేను అమ్మాలి'));
          context.go('/');
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(t('Sell something', 'ఏదైనా అమ్మండి')),
      ),
      body: listings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                t('Could not load your listings. If you were signed out, sign in again.',
                    'మీ లిస్టింగ్‌లు లోడ్ కాలేదు. సైన్ అవుట్ అయి ఉంటే మళ్లీ సైన్ ఇన్ చేయండి.'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, children: [
                OutlinedButton(
                  key: const Key('askodoxListingsRetry'),
                  onPressed: () => ref.invalidate(_myListingsProvider),
                  child: Text(t('Retry', 'మళ్లీ ప్రయత్నించండి')),
                ),
                FilledButton(
                  key: const Key('askodoxListingsSignIn'),
                  onPressed: () => context.push('/onboarding?signin=1'),
                  child: Text(t('Sign in', 'సైన్ ఇన్')),
                ),
              ]),
            ]),
          ),
        ),
        data: (items) => items.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    t('No listings yet. Tap "Sell something" and tell ASKODOX what you sell.',
                        'ఇంకా లిస్టింగ్‌లు లేవు. "ఏదైనా అమ్మండి" నొక్కి ASKODOX కి చెప్పండి.'),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
                for (final item in items)
                  Card(
                    key: ValueKey('askodoxMyListing-${item['id']}'),
                    child: ListTile(
                      key: ValueKey('askodoxEditListing-${item['id']}'),
                      onTap: () => edit(item),
                      leading: const Icon(Icons.edit_outlined),
                      title: Text('${item['subject'] ?? ''}'),
                      subtitle: Text([
                        if (item['price'] != null) '₹${item['price']}',
                        if ('${item['variant'] ?? ''}'.isNotEmpty) '${item['variant']}',
                        if ('${item['stock_status'] ?? ''}' == 'IN_STOCK') t('In stock', 'స్టాక్ ఉంది'),
                        if ('${item['stock_status'] ?? ''}' == 'OUT_OF_STOCK') t('Out of stock', 'స్టాక్ లేదు'),
                        if ('${item['location_label'] ?? ''}'.isNotEmpty) '${item['location_label']}',
                      ].join(' • ')),
                      trailing: TextButton(
                        key: ValueKey('askodoxRemoveListing-${item['id']}'),
                        onPressed: () => remove(item),
                        child: Text(t('Remove', 'తీసివేయండి')),
                      ),
                    ),
                  ),
              ]),
      ),
    );
  }
}
