import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../home/application/conversation_archive.dart';

/// History filter chips. `null` is "All".
typedef _Filter = AskodoxConversationStatus?;

/// ASKODOX History: every real conversation, filterable by status. Opening
/// one restores it exactly in Main Chat; "New ask" starts a clean chat.
class WatchlistScreen extends ConsumerStatefulWidget {
  const WatchlistScreen({super.key});

  @override
  ConsumerState<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends ConsumerState<WatchlistScreen> {
  _Filter _filter;

  void _open(AskodoxConversationSnapshot snapshot) {
    ref.read(askodoxChatRequestProvider.notifier).state =
        AskodoxChatRequest.restore(snapshot.id);
    context.go('/');
  }

  void _newAsk() {
    ref.read(askodoxChatRequestProvider.notifier).state =
        AskodoxChatRequest.newConversation();
    context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final isTelugu = Localizations.localeOf(context).languageCode == 'te';
    String t(String english, String telugu) => isTelugu ? telugu : english;
    final all = ref.watch(askodoxConversationArchiveProvider);
    final visible = _filter == null
        ? all
        : all.where((item) => item.status == _filter).toList();

    String statusLabel(AskodoxConversationStatus status) => switch (status) {
          AskodoxConversationStatus.active => t('Active', 'యాక్టివ్'),
          AskodoxConversationStatus.matched => t('Matched', 'మ్యాచ్ అయింది'),
          AskodoxConversationStatus.completed => t('Completed', 'పూర్తైంది'),
        };

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          t('History', 'చరిత్ర'),
          style: const TextStyle(color: Color(0xFF14213D), fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
        children: [
          Text(
            t('Continue where you left off', 'మీరు ఆపిన చోటు నుంచే కొనసాగించండి'),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF14213D)),
          ),
          const SizedBox(height: 6),
          Text(
            t(
              'Every ask, clarification, result and deal stays together as one ASKODOX timeline.',
              'మీ ప్రతి ప్రశ్న, వివరణ, ఫలితం మరియు డీల్ అన్నీ ఒకే ASKODOX టైమ్‌లైన్‌లో కలిసి ఉంటాయి.',
            ),
            style: const TextStyle(color: Color(0xFF667085), height: 1.4),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (filter, label) in <(_Filter, String)>[
                (null, t('All', 'అన్నీ')),
                (AskodoxConversationStatus.active, t('Active', 'యాక్టివ్')),
                (AskodoxConversationStatus.matched, t('Matched', 'మ్యాచ్ అయినవి')),
                (AskodoxConversationStatus.completed, t('Completed', 'పూర్తైనవి')),
              ])
                ChoiceChip(
                  key: ValueKey('historyFilter-${filter?.name ?? 'all'}'),
                  label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (visible.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                all.isEmpty
                    ? t('No conversations yet. Ask ASKODOX anything to get started.',
                        'ఇంకా సంభాషణలు లేవు. ASKODOXని ఏదైనా అడగండి.')
                    : t('Nothing here for this filter.', 'ఈ ఫిల్టర్‌లో ఏమీ లేవు.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF667085)),
              ),
            ),
          for (final item in visible)
            _HistoryCard(
              key: ValueKey('historyCard-${item.id}'),
              icon: switch (item.status) {
                AskodoxConversationStatus.active => Icons.chat_bubble_outline_rounded,
                AskodoxConversationStatus.matched => Icons.storefront_outlined,
                AskodoxConversationStatus.completed => Icons.task_alt_rounded,
              },
              title: item.title,
              status: statusLabel(item.status),
              time: _relativeTime(item.updatedAt, isTelugu),
              accent: switch (item.status) {
                AskodoxConversationStatus.active => const Color(0xFF1769FF),
                AskodoxConversationStatus.matched => const Color(0xFF10A53A),
                AskodoxConversationStatus.completed => const Color(0xFF8E5CF7),
              },
              onTap: () => _open(item),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('historyNewAsk'),
        backgroundColor: const Color(0xFF1769FF),
        foregroundColor: Colors.white,
        onPressed: _newAsk,
        icon: const Icon(Icons.add_rounded),
        label: Text(t('New ask', 'కొత్త ప్రశ్న'), style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
    );
  }

  static String _relativeTime(DateTime time, bool te) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return te ? 'ఇప్పుడే' : 'Just now';
    if (diff.inHours < 1) return te ? '${diff.inMinutes} నిమిషాల క్రితం' : '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return te ? '${diff.inHours} గంటల క్రితం' : '${diff.inHours} h ago';
    if (diff.inDays == 1) return te ? 'నిన్న' : 'Yesterday';
    return te ? '${diff.inDays} రోజుల క్రితం' : '${diff.inDays} days ago';
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.status,
    required this.time,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String status;
  final String time;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: Color(0xFFE5EAF2)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: accent.withValues(alpha: .12),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF14213D))),
                      const SizedBox(height: 5),
                      Row(children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Expanded(child: Text(status, style: const TextStyle(color: Color(0xFF667085)))),
                      ]),
                      const SizedBox(height: 4),
                      Text(time, style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Color(0xFF98A2B3)),
              ],
            ),
          ),
        ),
      );
}
