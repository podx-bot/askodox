import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../pos/data/pos_repository.dart';
import 'guide_session_logic.dart';

/// Owner 2026-11-26: a reminder of what is left in the setup or of ONE feature that fits what the person said. It sits
/// in the strip above the chat (Home only), never as a pop-up; "వద్దు" / "ఇక చూపించకు" stop it for good.
/// On only in `main()`; tests keep it off.
bool askodoxGuideReminderChip = false;

class AskodoxGuideRemindersNotifier extends StateNotifier<List<AskodoxGuideReminder>> {
  AskodoxGuideRemindersNotifier(this._repo) : super(const []);
  final AskodoxPosRepository _repo;
  bool _asked = false;

  /// The first time the strip is on screen only (a later refresh is asked for by the guide screen).
  void loadOnce(String language) {
    if (_asked) return;
    _asked = true;
    unawaited(refresh(language));
  }

  Future<void> refresh(String language) async {
    try {
      final rows = await _repo.guideReminders(language);
      state = [for (final r in rows) if (AskodoxGuideReminder.from(r) != null) AskodoxGuideReminder.from(r)!];
    } catch (_) {
      // Not signed in, or no connection: no chip, nothing to say.
    }
  }

  Future<void> dismiss(AskodoxGuideReminder r, {bool forever = false}) async {
    state = [for (final x in state) if (x.ref != r.ref) x];
    try {
      await _repo.guideDismiss(r.ref, forever: forever);
    } catch (_) {}
  }
}

final askodoxGuideRemindersProvider =
    StateNotifierProvider<AskodoxGuideRemindersNotifier, List<AskodoxGuideReminder>>((ref) => AskodoxGuideRemindersNotifier(ref.read(askodoxPosRepositoryProvider)));

/// The gold chips ("సెటప్ మిగిలింది", "ఇది మీకు తెలుసా?"): tap = open, ✕ = not now, long press = never again.
class AskodoxGuideReminderChips extends ConsumerWidget {
  const AskodoxGuideReminderChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!askodoxGuideReminderChip) return const SizedBox.shrink();
    final te = Localizations.localeOf(context).languageCode == 'te';
    final items = ref.watch(askodoxGuideRemindersProvider);
    Future<void>.microtask(() => ref.read(askodoxGuideRemindersProvider.notifier).loadOnce(te ? 'te' : 'en'));
    if (items.isEmpty) return const SizedBox.shrink();
    final control = ref.read(askodoxGuideRemindersProvider.notifier);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final r in items)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onLongPress: () => control.dismiss(r, forever: true),
                child: InputChip(
                  key: ValueKey('askodoxGuideReminder-${r.ref}'),
                  backgroundColor: const Color(0xFFFFF4D6),
                  avatar: const Icon(Icons.lightbulb_outline_rounded, size: 16, color: Color(0xFF8A5A00)),
                  label: Text(
                      r.kind == 'setup'
                          ? (te ? 'సెటప్ మిగిలింది: ${r.text}' : 'Setup left: ${r.text}')
                          : (te ? 'ఇది మీకు తెలుసా? ${r.text}' : 'Did you know? ${r.text}'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  onPressed: () => context.push(r.route),
                  onDeleted: () => control.dismiss(r),
                  deleteButtonTooltipMessage: te ? 'ఇప్పుడు వద్దు' : 'Not now',
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
