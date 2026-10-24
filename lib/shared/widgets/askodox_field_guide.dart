import 'package:flutter/material.dart';

import 'askodox_mascot.dart';

/// The small "?" next to a field: one press and ASKO explains what to type
/// there, with an example (English / Telugu from the app language). Used on
/// every form so a first-time user never has to guess.
class AskodoxFieldGuideButton extends StatelessWidget {
  const AskodoxFieldGuideButton({
    super.key,
    required this.titleEn,
    required this.titleTe,
    required this.en,
    required this.te,
    this.exampleEn,
    this.exampleTe,
  });

  final String titleEn;
  final String titleTe;
  final String en;
  final String te;
  final String? exampleEn;
  final String? exampleTe;

  @override
  Widget build(BuildContext context) {
    final telugu = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
    return IconButton(
      tooltip: telugu ? 'ఇక్కడ ఏం రాయాలి?' : 'What goes here?',
      visualDensity: VisualDensity.compact,
      icon: const Icon(Icons.help_outline, size: 20, color: Color(0xFF1769FF)),
      onPressed: () => askodoxShowFieldGuide(
        context,
        title: telugu ? titleTe : titleEn,
        text: telugu ? te : en,
        example: telugu ? exampleTe : exampleEn,
      ),
    );
  }
}

Future<void> askodoxShowFieldGuide(BuildContext context, {required String title, required String text, String? example}) {
  final telugu = Localizations.maybeLocaleOf(context)?.languageCode == 'te';
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        key: const Key('askodoxFieldGuideSheet'),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const AskodoxMascot(size: 34),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(fontSize: 14.5, height: 1.4)),
          if (example != null && example.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFF1F6FF), borderRadius: BorderRadius.circular(10)),
              child: Text('${telugu ? 'ఉదాహరణ' : 'Example'}: $example', style: const TextStyle(fontSize: 13.5)),
            ),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: () => Navigator.pop(ctx), child: Text(telugu ? 'అర్థమైంది' : 'Got it')),
          ),
        ]),
      ),
    ),
  );
}

/// Guide text for a catalogue detail (attribute spec from the server), built from
/// its own label, kind, options, unit and required flag -- same words for every
/// category, no per-category scripts.
({String en, String te, String? exampleEn, String? exampleTe}) askodoxAttributeGuide(Map spec) {
  final label = (spec['label'] as Map?) ?? const {};
  final en = '${label['en'] ?? spec['key']}';
  final te = '${label['te'] ?? en}';
  final options = [for (final o in (spec['options'] as List? ?? const [])) '$o'];
  final unit = '${spec['unit'] ?? ''}';
  final multi = spec['multi'] == true;
  final required = spec['required'] == true;
  final kind = '${spec['kind'] ?? 'text'}';
  final needEn = required ? 'Customers need this before they buy — please fill it.' : 'Optional, but customers find and trust filled items more.';
  final needTe = required ? 'కొనే ముందు కస్టమర్లకు ఇది కావాలి — దయచేసి నింపండి.' : 'ఐచ్ఛికం, కానీ నింపిన సరుకులను కస్టమర్లు ఎక్కువగా కనుగొంటారు, నమ్ముతారు.';
  switch (kind) {
    case 'choice':
      return (
        en: '${multi ? 'Tick every one that is true' : 'Pick the one that is true'} for this item: $en. $needEn',
        te: 'ఈ సరుకుకి $te — ${multi ? 'నిజమైనవన్నీ టిక్ చేయండి' : 'నిజమైన ఒక్కటి ఎంచుకోండి'}. $needTe',
        exampleEn: options.isEmpty ? null : options.take(3).join(' / '),
        exampleTe: options.isEmpty ? null : options.take(3).join(' / '),
      );
    case 'number':
      return (
        en: 'Type the number for "$en"${unit.isEmpty ? '' : ' in $unit'} — only the number, from the item itself. $needEn',
        te: '"$te" సంఖ్యను${unit.isEmpty ? '' : ' $unit లో'} టైప్ చేయండి — సరుకు మీద ఉన్నది మాత్రమే. $needTe',
        exampleEn: unit.isEmpty ? '2' : '2 $unit',
        exampleTe: unit.isEmpty ? '2' : '2 $unit',
      );
    default:
      return (
        en: 'Write "$en" in a few words, as it is on the item or its box. No phone numbers or links. $needEn',
        te: '"$te" ని కొన్ని పదాల్లో, సరుకు / డబ్బా మీద ఉన్నట్టే రాయండి. ఫోన్ నంబర్లు, లింకులు వద్దు. $needTe',
        exampleEn: null,
        exampleTe: null,
      );
  }
}
