import 'package:flutter/material.dart';

import '../../config/theme/askodox_look.dart';

/// The note under every screen that shows worked-out money (owner 2026-11-27; the wording changes only after the
/// lawyer's review, and only HERE).
const askodoxEstimateNoteTe =
    'గమనిక: ఇవి ఉజ్జాయింపు లెక్కలు మాత్రమే, ఖచ్చితమైనవి కావు. మీ స్వంత లెక్కలే సరైనవి. ASKODOX బాధ్యత వహించదు.';
const askodoxEstimateNoteEn =
    'Note: these are rough figures only, not exact. Your own accounts are the right ones. ASKODOX is not responsible.';

class AskodoxEstimateNote extends StatelessWidget {
  const AskodoxEstimateNote({super.key});

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Text(te ? askodoxEstimateNoteTe : askodoxEstimateNoteEn,
        key: const Key('askodoxEstimateNote'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 11.5, height: 1.4, color: AskodoxLook.muted));
  }
}
