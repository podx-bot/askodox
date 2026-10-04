import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// One staff-approved news / content item (LIVE rows from `/api/content`).
class AskodoxNewsItem {
  const AskodoxNewsItem({required this.id, required this.title, this.subtitle = '', this.url = '', this.source = ''});

  factory AskodoxNewsItem.fromJson(Map<String, Object?> j) => AskodoxNewsItem(
        id: '${j['id'] ?? ''}',
        title: '${j['title'] ?? ''}',
        subtitle: '${j['subtitle'] ?? ''}',
        url: '${j['destination_url'] ?? ''}' == 'null' ? '' : '${j['destination_url'] ?? ''}',
        source: '${j['source_name'] ?? ''}',
      );

  final String id, title, subtitle, url, source;
}

final askodoxNewsProvider = FutureProvider.autoDispose<List<AskodoxNewsItem>>((ref) async {
  final r = await ref.watch(apiClientProvider).get<Map<String, Object?>>('/api/content?limit=10');
  if (r is! ApiSuccess<Map<String, Object?>>) return const [];
  return [
    for (final item in (r.data['items'] as List? ?? const []))
      if (item is Map) AskodoxNewsItem.fromJson(Map<String, Object?>.from(item)),
  ];
});

/// "News & updates" in Updates: only what ASKODOX staff published; nothing
/// is shown (no placeholder) when there is none.
class AskodoxNewsSection extends ConsumerWidget {
  const AskodoxNewsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final items = ref.watch(askodoxNewsProvider).valueOrNull ?? const <AskodoxNewsItem>[];
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(key: const Key('askodoxNews'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(te ? 'వార్తలు & అప్‌డేట్స్' : 'News & updates',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      for (final n in items)
        Card(
          child: ListTile(
            leading: const Icon(Icons.article_outlined),
            title: Text(n.title, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text([n.source, n.subtitle].where((s) => s.isNotEmpty).join(' · '),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: n.url.isEmpty ? null : () => launchUrl(Uri.parse(n.url), mode: LaunchMode.externalApplication),
          ),
        ),
    ]);
  }
}
