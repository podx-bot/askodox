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
/// Remove. New listings are made by telling ASKODOX ("I want to sell ...").
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
        error: (_, __) => Center(child: Text(t('Could not load your listings.', 'మీ లిస్టింగ్‌లు లోడ్ కాలేదు.'))),
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
                      title: Text('${item['subject'] ?? ''}'),
                      subtitle: Text([
                        if (item['price'] != null) '₹${item['price']}',
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
