import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_repository.dart';

bool askodoxPosTe(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

String askodoxPosT(BuildContext context, String en, String te) => askodoxPosTe(context) ? te : en;

/// The business the screens below work on (role + permissions come from the server).
final askodoxPosBusinessProvider = FutureProvider.autoDispose.family<AskodoxJson, String>(
    (ref, id) => ref.watch(askodoxPosRepositoryProvider).business(id));

bool askodoxPosCan(AskodoxJson business, String permission) =>
    (business['permissions'] as List? ?? const []).map((e) => '$e').contains(permission);

String askodoxPosToday([DateTime? now]) {
  final d = (now ?? DateTime.now()).toLocal();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
  });

  final TextEditingController controller;
  final String label;
  final bool number;
  final bool decimal;
  final String? hint;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          maxLength: maxLength,
          onChanged: onChanged,
          keyboardType: number ? TextInputType.numberWithOptions(decimal: decimal) : TextInputType.text,
          inputFormatters: number ? [FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]'))] : null,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder(), isDense: true,
              counterText: ''),
        ),
      );
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
