/// One concise clarification when a need is genuinely ambiguous, asked
/// BEFORE any search ("నాకు battery TV కావాలి" could be a portable
/// battery-powered TV, a TV for an inverter/battery backup, or a battery for
/// a TV remote). ASKODOX asks once instead of guessing.
class AskodoxClarificationOption {
  const AskodoxClarificationOption({
    required this.label,
    required this.teluguLabel,
    required this.subject,
    required this.keywords,
  });

  final String label;
  final String teluguLabel;

  /// The precise subject the search runs for once this is chosen.
  final String subject;
  final List<String> keywords;
}

class AskodoxClarification {
  const AskodoxClarification({
    required this.key,
    required this.question,
    required this.teluguQuestion,
    required this.options,
    required this.trigger,
    this.alreadyClear = const [],
  });

  final String key;
  final String question;
  final String teluguQuestion;
  final List<AskodoxClarificationOption> options;
  final RegExp trigger;

  /// Words that already make the need unambiguous (no question needed).
  final List<String> alreadyClear;
}

final askodoxClarifications = <AskodoxClarification>[
  AskodoxClarification(
    key: 'battery_tv',
    trigger: RegExp(r'battery\s*(tv|television|టీవీ)|బ్యాటరీ\s*(tv|టీవీ)', caseSensitive: false),
    alreadyClear: const ['portable', 'rechargeable', 'inverter', 'backup', 'remote', 'పోర్టబుల్', 'ఇన్వర్టర్', 'రిమోట్'],
    question: 'Do you mean a portable TV that runs on a battery, a TV for inverter/battery backup, or a battery for a TV remote?',
    teluguQuestion: 'మీకు బ్యాటరీతో నడిచే పోర్టబుల్ టీవీ కావాలా, ఇన్వర్టర్/బ్యాటరీ బ్యాకప్‌తో వాడే టీవీ కావాలా, లేక టీవీ రిమోట్ బ్యాటరీ కావాలా?',
    options: const [
      AskodoxClarificationOption(
        label: 'Portable battery TV',
        teluguLabel: 'పోర్టబుల్ బ్యాటరీ టీవీ',
        subject: 'portable rechargeable battery TV',
        keywords: ['portable', 'rechargeable', 'runs on battery', 'పోర్టబుల్'],
      ),
      AskodoxClarificationOption(
        label: 'TV for inverter / battery backup',
        teluguLabel: 'ఇన్వర్టర్ బ్యాకప్ టీవీ',
        subject: 'low power TV for inverter battery backup',
        keywords: ['inverter', 'backup', 'power cut', 'ఇన్వర్టర్', 'బ్యాకప్'],
      ),
      AskodoxClarificationOption(
        label: 'TV remote battery',
        teluguLabel: 'టీవీ రిమోట్ బ్యాటరీ',
        subject: 'TV remote batteries',
        keywords: ['remote', 'రిమోట్'],
      ),
    ],
  ),
  AskodoxClarification(
    key: 'tablet',
    trigger: RegExp(r'\btablets?\b|టాబ్లెట్', caseSensitive: false),
    alreadyClear: const ['android', 'ipad', 'samsung', 'inch', 'wifi', 'mg', 'medicine', 'paracetamol', 'pharmacy', 'మందు'],
    question: 'Do you mean a tablet device (like an Android tablet or iPad) or medicine tablets?',
    teluguQuestion: 'మీకు టాబ్లెట్ డివైస్ (Android/iPad) కావాలా, లేక మందుల టాబ్లెట్లు కావాలా?',
    options: const [
      AskodoxClarificationOption(label: 'Tablet device', teluguLabel: 'టాబ్లెట్ డివైస్', subject: 'tablet device', keywords: ['device', 'android', 'ipad', 'డివైస్']),
      AskodoxClarificationOption(label: 'Medicine tablets', teluguLabel: 'మందుల టాబ్లెట్లు', subject: 'medicine tablets from pharmacy', keywords: ['medicine', 'pharmacy', 'మందు']),
    ],
  ),
  AskodoxClarification(
    key: 'mouse',
    trigger: RegExp(r'\bmouse\b', caseSensitive: false),
    alreadyClear: const ['computer', 'wireless', 'usb', 'gaming', 'bluetooth', 'trap', 'pest', 'rat'],
    question: 'Do you mean a computer mouse, or help with a mouse/rat problem (trap or pest control)?',
    teluguQuestion: 'మీకు కంప్యూటర్ మౌస్ కావాలా, లేక ఎలుకల సమస్యకు (ట్రాప్/పెస్ట్ కంట్రోల్) సహాయం కావాలా?',
    options: const [
      AskodoxClarificationOption(label: 'Computer mouse', teluguLabel: 'కంప్యూటర్ మౌస్', subject: 'computer mouse', keywords: ['computer', 'wireless', 'usb', 'కంప్యూటర్']),
      AskodoxClarificationOption(label: 'Mouse trap / pest control', teluguLabel: 'ఎలుకల ట్రాప్ / పెస్ట్ కంట్రోల్', subject: 'mouse trap pest control', keywords: ['trap', 'pest', 'rat', 'ఎలుక']),
    ],
  ),
];

/// The clarification a new request needs, or null when it is clear.
AskodoxClarification? askodoxClarificationFor(String text) {
  final lower = text.toLowerCase();
  for (final clarification in askodoxClarifications) {
    if (!clarification.trigger.hasMatch(lower)) continue;
    if (clarification.alreadyClear.any(lower.contains)) return null;
    return clarification;
  }
  return null;
}

/// The option a reply picks: its number ("2"), label, or a keyword.
AskodoxClarificationOption? askodoxResolveClarification(
  AskodoxClarification clarification,
  String reply,
) {
  final lower = reply.trim().toLowerCase();
  final index = int.tryParse(lower);
  if (index != null && index >= 1 && index <= clarification.options.length) {
    return clarification.options[index - 1];
  }
  for (final option in clarification.options) {
    if (lower == option.label.toLowerCase() || reply.trim() == option.teluguLabel) {
      return option;
    }
  }
  for (final option in clarification.options) {
    if (option.keywords.any(lower.contains)) return option;
  }
  return null;
}

AskodoxClarification? askodoxClarificationByKey(String? key) {
  for (final clarification in askodoxClarifications) {
    if (clarification.key == key) return clarification;
  }
  return null;
}
