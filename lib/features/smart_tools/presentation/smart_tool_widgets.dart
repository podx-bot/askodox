import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/construction_calculators.dart';
import '../domain/smart_tool_catalog.dart';

bool askodoxToolsTe(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

/// Parses a typed number ("12", "12.5", "1,200"); null when empty / invalid.
double? askodoxParseNumber(String text) {
  final cleaned = text.replaceAll(',', '').trim();
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

class AskodoxNumberField extends StatelessWidget {
  const AskodoxNumberField({
    super.key,
    required this.controller,
    required this.label,
    this.suffix,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onChanged: onChanged,
          decoration: InputDecoration(
            labelText: label,
            suffixText: suffix,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
}

/// Result card: lines, then assumptions and warnings -- always shown so an
/// estimate is never mistaken for a verified figure.
class AskodoxCalcResultCard extends StatelessWidget {
  const AskodoxCalcResultCard({super.key, required this.result, this.error});

  final AskodoxCalcResult? result;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final te = askodoxToolsTe(context);
    final scheme = Theme.of(context).colorScheme;
    if (error != null) {
      return Card(
        key: const Key('askodoxToolError'),
        color: scheme.errorContainer,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
      );
    }
    final r = result;
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(te ? 'విలువలు నమోదు చేయండి.' : 'Enter the values to see the estimate.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return Card(
      key: const Key('askodoxToolResult'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(te ? 'అంచనా' : 'Estimate', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          for (final line in r.lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Expanded(child: Text(te ? line.labelTe : line.labelEn)),
                Text(line.formatted(), style: const TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
          if (r.assumptions.isNotEmpty) ...[
            const Divider(height: 20),
            Text(te ? 'అంచనాలు (assumptions)' : 'Assumptions',
                style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
            for (final a in r.assumptions)
              Text('• $a', style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
          ],
          for (final w in r.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 16, color: scheme.tertiary),
                const SizedBox(width: 6),
                Expanded(child: Text(w, style: const TextStyle(fontSize: 12.5))),
              ]),
            ),
        ]),
      ),
    );
  }
}

String askodoxReadinessLabel(AskodoxToolReadiness readiness, bool te) => switch (readiness) {
      AskodoxToolReadiness.ready => te ? 'సిద్ధం' : 'Ready',
      AskodoxToolReadiness.hardwareUnverified =>
        te ? 'ఫోన్‌లో ఇంకా పరీక్షించలేదు' : 'Not yet verified on a phone',
      AskodoxToolReadiness.needsExternalDevice => te ? 'బయటి పరికరం కావాలి' : 'Needs an external device',
      AskodoxToolReadiness.comingSoon => te ? 'త్వరలో' : 'Coming soon',
    };

String askodoxNeedLabel(AskodoxToolNeed need, bool te) => switch (need) {
      AskodoxToolNeed.phoneSensor => te ? 'ఫోన్ సెన్సార్లు' : 'Phone sensors',
      AskodoxToolNeed.camera => te ? 'కెమెరా' : 'Camera',
      AskodoxToolNeed.cameraAi => te ? 'కెమెరా + AI' : 'Camera + AI',
      AskodoxToolNeed.arCore => 'ARCore',
      AskodoxToolNeed.externalSensor => te ? 'బయటి సెన్సార్' : 'External sensor',
      AskodoxToolNeed.bluetoothDevice => te ? 'బ్లూటూత్ పరికరం' : 'Bluetooth device',
      AskodoxToolNeed.usbAdapter => te ? 'USB అడాప్టర్' : 'USB adapter',
      AskodoxToolNeed.cloudApi => te ? 'ఇంటర్నెట్ (AI సర్వీస్)' : 'Internet (AI service)',
      AskodoxToolNeed.manualInput => te ? 'మీరు టైప్ చేసే కొలతలు' : 'Your typed measurements',
    };

class AskodoxToolSafetyNote extends StatelessWidget {
  const AskodoxToolSafetyNote(this.toolId, {super.key});
  final String toolId;

  @override
  Widget build(BuildContext context) {
    final note = askodoxToolById(toolId)?.safetyNote;
    if (note == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.shield_outlined, size: 16),
        const SizedBox(width: 6),
        Expanded(child: Text(note, style: const TextStyle(fontSize: 12.5))),
      ]),
    );
  }
}
