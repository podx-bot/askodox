import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';
import '../../home/application/conversation_archive.dart';
import '../../profile/data/user_profile_repository.dart';
import '../data/catalogue_repository.dart';
import 'catalogue_widgets.dart';

final _listingQueryProvider = StateProvider.autoDispose<String>((ref) => '');

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
      // Safe removal: the seller confirms first (buyers stop seeing it).
      final sure = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(t('Remove this listing?', 'ఈ లిస్టింగ్ తీసివేయాలా?')),
          content: Text('${item['subject'] ?? ''}\n${t('Buyers will no longer see it.', 'కొనుగోలుదారులకు ఇక కనిపించదు.')}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(t('Keep', 'ఉంచండి'))),
            FilledButton(
              key: const Key('askodoxConfirmRemoveListing'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(t('Remove', 'తీసివేయండి')),
            ),
          ],
        ),
      );
      if (sure != true || !context.mounted) return;
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

    // Ready-made catalogue (ONE data-driven engine for every category): pick
    // a business type, choose items, add your price / details / photo,
    // review, then publish. Nothing is published without the seller's tap.
    Future<void> openCatalogue() async {
      final lang = Localizations.localeOf(context).languageCode;
      final repo = ref.read(askodoxCatalogueRepositoryProvider);
      final templates = await repo.templates();
      if (!context.mounted) return;
      if (templates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(t('Ready-made catalogues are not available right now.',
                'రెడీమేడ్ కేటలాగ్‌లు ఇప్పుడు అందుబాటులో లేవు.'))));
        return;
      }
      final key = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .8),
            child: ListView(shrinkWrap: true, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(t('Choose your business type', 'మీ వ్యాపార రకం ఎంచుకోండి'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              ),
              for (final tpl in templates)
                ListTile(
                  key: ValueKey('askodoxCatalogTemplate-${tpl.key}'),
                  leading: const Icon(Icons.category_outlined),
                  title: Text(tpl.names[lang] ?? tpl.names['en'] ?? tpl.key),
                  subtitle: Text('${tpl.items} ${t('ready-made items', 'రెడీమేడ్ ఐటమ్స్')}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(sheet, tpl.key),
                ),
            ]),
          ),
        ),
      );
      if (key == null || !context.mounted) return;
      final template = await repo.template(key);
      if (template == null || !context.mounted) return;
      AskodoxUserProfile? profile;
      try {
        profile = await ref.read(askodoxUserProfileProvider.future);
      } catch (_) {
        profile = null;
      }
      if (!context.mounted) return;
      final result = await showModalBottomSheet<AskodoxCataloguePublishResult>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => AskodoxCatalogueEditorSheet(
          template: template,
          categoryKeys: {for (final c in template.categories) c.key},
          lang: lang,
          shopName: profile?.businessName ?? profile?.name,
          shopAddress: profile?.businessAddress ?? profile?.address,
        ),
      );
      if (result == null || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        key: const Key('askodoxCatalogPublished'),
        content: Text(result.ok
            ? t('${result.published} published · ${result.drafts} saved as drafts.',
                '${result.published} ప్రచురించబడ్డాయి · ${result.drafts} డ్రాఫ్ట్‌లుగా సేవ్.')
            : t('Could not publish (${result.error}).', 'ప్రచురించలేకపోయాం (${result.error}).')),
      ));
      ref.invalidate(_myListingsProvider);
    }

    final base = ref.watch(appConfigProvider).apiBaseUrl;
    Widget thumb(Map<String, Object?> item) {
      final media = '${item['image_media_id'] ?? ''}';
      // Only the seller's OWN uploaded photo -- never a sample image.
      if (base != null && media.startsWith('catalog-photo:')) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.network(base.resolve('/api/catalog/photos/${item['id']}').toString(),
              width: 48, height: 48, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported_outlined)),
        );
      }
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: const Color(0xFFEFF3FA), borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF667085)),
      );
    }

    final query = ref.watch(_listingQueryProvider).trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: Text(t('My listings', 'నా లిస్టింగ్‌లు')), actions: [
        TextButton.icon(
          key: const Key('askodoxOpenCatalogTemplates'),
          onPressed: openCatalogue,
          icon: const Icon(Icons.auto_awesome_mosaic_outlined),
          label: Text(t('Ready-made catalog', 'రెడీమేడ్ కేటలాగ్')),
        ),
      ]),
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
            : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                TextField(
                  key: const Key('askodoxListingSearch'),
                  onChanged: (v) => ref.read(_listingQueryProvider.notifier).state = v,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: t('Search your ${items.length} listings', 'మీ ${items.length} లిస్టింగ్‌లలో వెతకండి'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                const SizedBox(height: 8),
                for (final item in items)
                  if (query.isEmpty ||
                      '${item['subject'] ?? ''} ${item['variant'] ?? ''}'.toLowerCase().contains(query))
                  Card(
                    key: ValueKey('askodoxMyListing-${item['id']}'),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE3E9F3))),
                    child: ListTile(
                      key: ValueKey('askodoxEditListing-${item['id']}'),
                      onTap: () => edit(item),
                      leading: thumb(item),
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
