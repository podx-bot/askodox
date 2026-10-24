import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../guide/guide_watch.dart';
import '../data/pos_repository.dart';

bool askodoxPosTe(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

String askodoxPosT(BuildContext context, String en, String te) => askodoxPosTe(context) ? te : en;

/// The business the screens below work on (role + permissions come from the server).
final askodoxPosBusinessProvider = FutureProvider.autoDispose.family<AskodoxJson, String>(
    (ref, id) => ref.watch(askodoxPosRepositoryProvider).business(id));

/// Where an item is offered: the item's own choice, else the shop default (pos / online / both).
String askodoxPosChannel(AskodoxJson product, Object? shopDefault) {
  const known = {'pos', 'online', 'both'};
  final own = '${product['channel'] ?? ''}';
  if (known.contains(own)) return own;
  final fallback = '${shopDefault ?? ''}';
  return known.contains(fallback) ? fallback : 'pos';
}

String askodoxPosChannelLabel(String channel, bool te) => switch (channel) {
      'online' => te ? 'ఆన్‌లైన్ మాత్రమే' : 'Online only',
      'both' => te ? 'రెండూ' : 'Both',
      _ => te ? 'POS మాత్రమే' : 'POS only',
    };

bool askodoxPosCan(AskodoxJson business, String permission) =>
    (business['permissions'] as List? ?? const []).map((e) => '$e').contains(permission);

String askodoxPosToday([DateTime? now]) {
  final d = (now ?? DateTime.now()).toLocal();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// A sample answer for a box, by what the box asks (one table for every POS form, en + te), so the
/// example always sits inside the box. Field TYPES, never categories; first match wins.
const _askodoxPosExamples = <(List<String>, String, String)>[
  (['gstin'], '36ABCDE1234F1Z5', '36ABCDE1234F1Z5'),
  (['hsn'], 'the 4-8 digit code on your purchase bill', 'కొనుగోలు బిల్లుపై ఉన్న 4-8 అంకెల కోడ్'),
  (['barcode', 'బార్‌కోడ్'], '8901234567890', '8901234567890'),
  (['batch', 'బ్యాచ్'], 'B2410', 'B2410'),
  (['expiry', 'ఎక్స్‌పైరీ'], '2027-03-31', '2027-03-31'),
  (['phone', 'mobile', 'ఫోన్', 'మొబైల్'], '9876543210', '9876543210'),
  (['utr', 'reference', 'రిఫరెన్స్'], '412345678901', '412345678901'),
  (['bill number', 'బిల్లు నంబర్'], 'INV-2041', 'INV-2041'),
  (['prefix', 'ముందు అక్షరాలు'], 'LK', 'LK'),
  (['telugu name', 'తెలుగు పేరు'], 'కంది పప్పు', 'కంది పప్పు'),
  (['shop name', 'షాపు పేరు'], 'Lakshmi Kirana', 'లక్ష్మీ కిరాణా'),
  (['address', 'చిరునామా'], 'Main Road, near bus stand', 'మెయిన్ రోడ్, బస్టాండ్ దగ్గర'),
  (['reason', 'కారణం'], 'packet was damaged', 'ప్యాకెట్ పగిలింది'),
  (['note', 'నోట్'], 'less spicy', 'తక్కువ కారం'),
  (['tare', 'ట్రే'], '0.150', '0.150'),
  (['weight', 'బరువు'], '1.250', '1.250'),
  (['how many', 'ఎన్ని'], '12', '12'),
  (['stock', 'స్టాక్'], '25', '25'),
  (['credit limit', 'బాకీ పరిమితి'], '5000', '5000'),
  (['quantity', 'qty', 'సంఖ్య', 'పరిమాణం'], '2', '2'),
  (['₹', 'price', 'amount', 'cash', 'cost', 'ధర', 'మొత్తం', 'నగదు'], '250', '250'),
  (['name', 'పేరు'], 'Ramesh Stores', 'రమేష్ స్టోర్స్'),
];

(String, String)? askodoxPosFieldExample(String label) {
  final l = label.toLowerCase();
  for (final (keys, en, te) in _askodoxPosExamples) {
    if (keys.any(l.contains)) return (en, te);
  }
  return null;
}

class AskodoxPosField extends StatelessWidget {
  const AskodoxPosField({
    super.key,
    required this.controller,
    required this.label,
    this.number = false,
    this.decimal = true,
    this.hint,
    this.maxLength,
    this.onChanged,
    this.guideEn,
    this.guideTe,
    this.exampleEn,
    this.exampleTe,
  });

  final TextEditingController controller;
  final String label;
  final bool number;
  final bool decimal;
  final String? hint;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  /// The "?" guide for this field (what to type + example).
  final String? guideEn;
  final String? guideTe;
  final String? exampleEn;
  final String? exampleTe;

  String? _example(BuildContext context) {
    final te = askodoxPosTe(context);
    final en = exampleEn;
    if (en != null && en.isNotEmpty) return te ? 'ఉదా: ${exampleTe ?? en}' : 'e.g. $en';
    final generic = askodoxPosFieldExample(label);
    if (generic == null) return null;
    return te ? 'ఉదా: ${generic.$2}' : 'e.g. ${generic.$1}';
  }

  @override
  Widget build(BuildContext context) {
    final field = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        maxLength: maxLength,
        onChanged: onChanged,
        keyboardType: number ? TextInputType.numberWithOptions(decimal: decimal) : TextInputType.text,
        inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]'))] : null,
        // The example sits INSIDE the box (grey) so nobody has to ask what to write.
        decoration: InputDecoration(
            labelText: label,
            hintText: hint ?? _example(context),
            floatingLabelBehavior: (hint ?? _example(context)) == null ? null : FloatingLabelBehavior.always,
            border: const OutlineInputBorder(),
            isDense: true,
            counterText: ''),
      ),
    );
    // No "?" icon: the guide on the left offers this text when the person stops on the empty box.
    if (guideEn == null) return field;
    return AskodoxFieldGuideInfo(
      titleEn: label, titleTe: label, en: guideEn!, te: guideTe ?? guideEn!,
      exampleEn: exampleEn, exampleTe: exampleTe ?? exampleEn,
      child: field,
    );
  }
}

class AskodoxPosError extends StatelessWidget {
  const AskodoxPosError({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final text = error is AskodoxPosException ? (error as AskodoxPosException).message(te) : (te ? 'లోడ్ కాలేదు.' : 'Could not load.');
    return ListView(children: [
      ListTile(
        key: const Key('askodoxPosError'),
        leading: const Icon(Icons.error_outline),
        title: Text(text),
        trailing: onRetry == null ? null : TextButton(onPressed: onRetry, child: Text(te ? 'మళ్ళీ' : 'Retry')),
      ),
    ]);
  }
}

void askodoxPosSnack(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
