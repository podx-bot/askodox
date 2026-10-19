import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/companion/relationship.dart';
import '../../features/home/presentation/question_mic.dart';
import '../widgets/askodox_mascot.dart';
import 'smart_guide_corrections.dart';

/// One form field the Smart Guide may correct.
class AskodoxGuideTarget {
  const AskodoxGuideTarget(this.label, this.controller);
  final String label;
  final TextEditingController controller;
}

/// "Tell ASKO what to change": typed or spoken corrections for the form's
/// fields. Shows old -> new and changes NOTHING until the person confirms;
/// every other field (the draft) stays exactly as it was.
class AskodoxSmartGuideBar extends ConsumerStatefulWidget {
  const AskodoxSmartGuideBar({super.key, required this.targets, this.onApplied});

  /// Field id ([AskodoxGuideFieldId]) -> its label and controller.
  final Map<String, AskodoxGuideTarget> targets;
  final ValueChanged<Map<String, String>>? onApplied;

  @override
  ConsumerState<AskodoxSmartGuideBar> createState() => _AskodoxSmartGuideBarState();
}

class _AskodoxSmartGuideBarState extends ConsumerState<AskodoxSmartGuideBar> {
  final _input = TextEditingController();

  bool get _te => Localizations.maybeLocaleOf(context)?.languageCode == 'te';
  String _t(String en, String te) => _te ? te : en;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _propose(String said) async {
    final text = said.trim();
    if (text.isEmpty) return;
    final proposed = askodoxParseCorrections(text, widget.targets.keys.toSet());
    final changes = askodoxDiff(
      {for (final e in widget.targets.entries) e.key: e.value.controller.text},
      proposed,
    );
    final relation = ref.read(askodoxRelationProvider);
    if (changes.isEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        key: const Key('askodoxGuideNoChange'),
        content: Text(askodoxAddressed(
            _t('I could not tell which box to change. Say it like: price 300, size 8',
                'ఏ బాక్స్ మార్చాలో అర్థం కాలేదు. ఇలా చెప్పండి: ధర 300, సైజు 8'),
            relation,
            telugu: _te)),
      ));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        key: const Key('askodoxGuideConfirm'),
        title: Row(children: [
          const AskodoxMascot(size: 36),
          const SizedBox(width: 8),
          Expanded(child: Text(_t('Change these?', 'ఇవి మార్చాలా?'), style: const TextStyle(fontSize: 17))),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final c in changes)
            Padding(
              key: ValueKey('askodoxGuideChange-${c.field}'),
              padding: const EdgeInsets.only(bottom: 6),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${widget.targets[c.field]!.label}: ',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                TextSpan(
                    text: c.before.isEmpty ? _t('(empty)', '(ఖాళీ)') : c.before,
                    style: const TextStyle(decoration: TextDecoration.lineThrough, color: Color(0xFF98A2B3))),
                const TextSpan(text: '  →  '),
                TextSpan(text: c.after, style: const TextStyle(color: Color(0xFF067647), fontWeight: FontWeight.w700)),
              ])),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: Text(_t('No', 'వద్దు'))),
          FilledButton(
              key: const Key('askodoxGuideApply'),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text(_t('Yes, change', 'అవును, మార్చు'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    for (final c in changes) {
      widget.targets[c.field]!.controller.text = c.after;
    }
    _input.clear();
    widget.onApplied?.call({for (final c in changes) c.field: c.after});
  }

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('askodoxSmartGuideBar'),
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F1FF),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          const AskodoxMascot(size: 28),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              key: const Key('askodoxSmartGuideInput'),
              controller: _input,
              textInputAction: TextInputAction.done,
              onSubmitted: _propose,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                hintText: _t('Tell ASKO what to change: price 300, size 8', 'ASKOకి చెప్పండి: ధర 300, సైజు 8'),
                hintStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ),
          AskodoxQuestionMic(lang: _te ? 'te' : 'en', onText: _propose),
          IconButton(
            key: const Key('askodoxSmartGuideSend'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.send_rounded, size: 20, color: Color(0xFF6C4DFF)),
            onPressed: () => _propose(_input.text),
          ),
        ]),
      );
}
