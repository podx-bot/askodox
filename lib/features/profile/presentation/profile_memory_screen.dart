import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/backend_providers.dart';
import '../data/profile_memory_repository.dart';

/// Profile -> "What ASKODOX remembers": the needs / offers kept from the
/// person's conversations, by role. They can correct, close, delete one or
/// all, or switch remembering off. Private unless they publish with consent.
class ProfileMemoryScreen extends ConsumerWidget {
  const ProfileMemoryScreen({super.key});

  static String roleLabel(String role, bool te) => switch (role) {
        'buyer' => te ? 'కొనుగోలుదారు' : 'Buyer',
        'seller' => te ? 'విక్రేత' : 'Seller',
        'service_provider' => te ? 'సేవ అందించేవారు' : 'Service provider',
        'service_taker' => te ? 'సేవ / ఉద్యోగం కోరేవారు' : 'Service taker (services / jobs)',
        _ => role,
      };

  static String statusLabel(String status, bool te) => switch (status) {
        'active' => te ? 'యాక్టివ్' : 'Active',
        'updated' => te ? 'నవీకరించబడింది' : 'Updated',
        'completed' => te ? 'పూర్తయింది' : 'Completed',
        'cancelled' => te ? 'రద్దు' : 'Cancelled',
        'expired' => te ? 'గడువు ముగిసింది' : 'Expired',
        _ => status,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    String t(String en, String tel) => te ? tel : en;
    final signedIn = ref.watch(authSessionProvider).user != null;
    final memory = ref.watch(profileMemoryProvider);
    final repo = ref.read(profileMemoryRepositoryProvider);
    Future<void> act(Future<bool> Function() call) async {
      final ok = await call();
      ref.invalidate(profileMemoryProvider);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('Could not save. Try again.', 'సేవ్ కాలేదు. మళ్లీ ప్రయత్నించండి.'))));
      }
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('What ASKODOX remembers', 'ASKODOX గుర్తుంచుకున్నవి'))),
      body: !signedIn
          ? Center(child: Text(t('Sign in to see your memory.', 'సైన్ ఇన్ చేయండి.')))
          : memory.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: TextButton(
                  key: const Key('askodoxMemoryRetry'),
                  onPressed: () => ref.invalidate(profileMemoryProvider),
                  child: Text(t('Could not load. Retry', 'లోడ్ కాలేదు. మళ్లీ')),
                ),
              ),
              data: (data) {
                final items = data?.items ?? const <AskodoxMemoryItem>[];
                final byRole = <String, List<AskodoxMemoryItem>>{};
                for (final item in items) {
                  byRole.putIfAbsent(item.role, () => []).add(item);
                }
                return ListView(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    SwitchListTile(
                      key: const Key('askodoxMemoryEnabled'),
                      contentPadding: EdgeInsets.zero,
                      value: data?.enabled ?? true,
                      title: Text(t('Remember from my conversations', 'నా సంభాషణల నుంచి గుర్తుంచుకో')),
                      subtitle: Text(t(
                          'Private to you. Never OTPs, passwords or card numbers. Nothing is published or shared without your consent.',
                          'మీకు మాత్రమే. OTP, పాస్‌వర్డ్, కార్డ్ నంబర్లు ఎప్పుడూ నిల్వ చేయం. మీ అనుమతి లేకుండా ఏదీ పబ్లిష్ / షేర్ చేయం.')),
                      onChanged: (on) => act(() => repo.setEnabled(on)),
                    ),
                    if (items.isEmpty)
                      Padding(
                        key: const Key('askodoxMemoryEmpty'),
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(t('Nothing remembered yet.', 'ఇంకా ఏదీ గుర్తుంచుకోలేదు.')),
                      ),
                    for (final entry in byRole.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Text(roleLabel(entry.key, te),
                            key: ValueKey('askodoxMemoryRole-${entry.key}'),
                            style: Theme.of(context).textTheme.titleSmall),
                      ),
                      for (final item in entry.value)
                        Card(
                          key: ValueKey('askodoxMemoryItem-${item.id}'),
                          child: ListTile(
                            title: Text(item.subject),
                            subtitle: Text([
                              statusLabel(item.status, te),
                              if (item.category.isNotEmpty) item.category,
                              for (final e in item.details.entries.take(4)) '${e.key}: ${e.value}',
                            ].join(' · ')),
                            trailing: PopupMenuButton<String>(
                              key: ValueKey('askodoxMemoryMenu-${item.id}'),
                              onSelected: (choice) async {
                                switch (choice) {
                                  case 'edit':
                                    final text = await _ask(context, t('Correct it', 'సరిచేయండి'), item.subject);
                                    if (text != null && text.trim().isNotEmpty) {
                                      await act(() => repo.correct(item.id, {'subject': text.trim()}));
                                    }
                                  case 'completed' || 'cancelled' || 'active':
                                    await act(() => repo.correct(item.id, {'status': choice}));
                                  case 'delete':
                                    await act(() => repo.delete(item.id));
                                }
                              },
                              itemBuilder: (_) => [
                                PopupMenuItem(value: 'edit', child: Text(t('Correct', 'సరిచేయి'))),
                                PopupMenuItem(
                                    key: ValueKey('askodoxMemoryDone-${item.id}'),
                                    value: 'completed',
                                    child: Text(t('Mark completed', 'పూర్తయింది'))),
                                PopupMenuItem(value: 'cancelled', child: Text(t('Cancel', 'రద్దు'))),
                                if (item.status != 'active')
                                  PopupMenuItem(value: 'active', child: Text(t('Make active again', 'మళ్లీ యాక్టివ్'))),
                                PopupMenuItem(
                                    key: ValueKey('askodoxMemoryDelete-${item.id}'),
                                    value: 'delete',
                                    child: Text(t('Delete', 'తొలగించు'))),
                              ],
                            ),
                          ),
                        ),
                    ],
                    if (items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: OutlinedButton.icon(
                          key: const Key('askodoxMemoryDeleteAll'),
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: Text(t('Delete everything remembered', 'గుర్తుంచుకున్నవన్నీ తొలగించు')),
                          onPressed: () async {
                            final sure = await showDialog<bool>(
                              context: context,
                              builder: (dialog) => AlertDialog(
                                content: Text(t('Delete everything ASKODOX remembers? This cannot be undone.',
                                    'అన్నీ తొలగించాలా? ఇది తిరిగి రాదు.')),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(dialog, false), child: Text(t('Keep', 'ఉంచు'))),
                                  TextButton(
                                      key: const Key('askodoxMemoryDeleteAllConfirm'),
                                      onPressed: () => Navigator.pop(dialog, true),
                                      child: Text(t('Delete', 'తొలగించు'))),
                                ],
                              ),
                            );
                            if (sure == true) await act(repo.deleteAll);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  static Future<String?> _ask(BuildContext context, String title, String initial) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: TextField(key: const Key('askodoxMemoryEditField'), controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
          TextButton(
              key: const Key('askodoxMemoryEditSave'),
              onPressed: () => Navigator.pop(dialog, controller.text),
              child: const Text('Save')),
        ],
      ),
    );
  }
}
