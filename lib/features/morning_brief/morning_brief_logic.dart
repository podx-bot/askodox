/// Morning brief (owner 2026-11-27): the words of the three things to do today. Pure; the numbers come from the
/// server's real counts (`/morning-brief`), nothing is worked out or guessed here.
library;

class AskodoxBriefTask {
  const AskodoxBriefTask({
    required this.key,
    required this.action,
    required this.route,
    this.count = 0,
    this.name = '',
    this.days = 0,
    this.amountPaise,
  });

  final String key;
  final String action;
  final String route;
  final int count;
  final String name;
  final int days;
  final int? amountPaise;

  /// A row the app can show: a known kind with a page to open. Anything else is left out (an older app never shows
  /// a row it has no words for).
  static AskodoxBriefTask? from(Object? raw) {
    if (raw is! Map) return null;
    final key = '${raw['key'] ?? ''}';
    final route = '${raw['route'] ?? ''}';
    if (!askodoxBriefKinds.contains(key) || !route.startsWith('/')) return null;
    int number(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    return AskodoxBriefTask(
      key: key,
      action: '${raw['action'] ?? 'view'}',
      route: route,
      count: number(raw['count']),
      name: '${raw['name'] ?? ''}',
      days: number(raw['days']),
      amountPaise: raw['amount_paise'] == null ? null : number(raw['amount_paise']),
    );
  }
}

const askodoxBriefKinds = <String>{'dues', 'low_stock', 'winback', 'yesterday', 'my_bills', 'family', 'habit'};

List<AskodoxBriefTask> askodoxBriefTasks(Object? raw) => [
      if (raw is List)
        for (final row in raw)
          if (AskodoxBriefTask.from(row) != null) AskodoxBriefTask.from(row)!,
    ];

/// Whole rupees when there are no paise ("₹962"), else two places.
String askodoxBriefRupees(int paise) => paise % 100 == 0 ? '₹${paise ~/ 100}' : '₹${(paise / 100).toStringAsFixed(2)}';

bool askodoxBriefShowsMoney(List<AskodoxBriefTask> tasks) => tasks.any((t) => t.amountPaise != null);

const _daysTe = ['సోమవారం', 'మంగళవారం', 'బుధవారం', 'గురువారం', 'శుక్రవారం', 'శనివారం', 'ఆదివారం'];
const _daysEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// "శుభోదయం · శుక్రవారం" before noon, "నమస్తే · శుక్రవారం" after. [weekday] 0 = Monday (the server's India day).
String askodoxBriefGreeting(int weekday, int hour, bool te) {
  final day = (te ? _daysTe : _daysEn)[weekday.clamp(0, 6)];
  final hello = hour < 12 ? (te ? 'శుభోదయం' : 'Good morning') : (te ? 'నమస్తే' : 'Hello');
  return '$hello · $day';
}

String askodoxBriefHeadline(int tasks, bool te) {
  if (tasks <= 0) return te ? 'ఈ రోజు పనులన్నీ అయిపోయాయి' : 'Nothing waits for you today';
  if (tasks == 1) return te ? 'ఈ రోజు మీ దగ్గర ఒక పని' : 'One thing for you today';
  return te ? 'ఈ రోజు మీ దగ్గర $tasks పనులు' : '$tasks things for you today';
}

String askodoxBriefTitle(AskodoxBriefTask t, bool te) {
  final money = t.amountPaise == null ? '' : ' · ${askodoxBriefRupees(t.amountPaise!)}';
  switch (t.key) {
    case 'dues':
      return te ? '${t.count} బాకీలు గుర్తు చేయాలి' : '${t.count} dues to remind';
    case 'low_stock':
      final more = t.count > 1 ? ' +${t.count - 1}' : '';
      return te ? '${t.name}$more తక్కువ' : '${t.name}$more running low';
    case 'winback':
      return te ? '${t.count} మంది రెగ్యులర్లను మళ్ళీ పిలుద్దాం' : '${t.count} regulars to call back';
    case 'yesterday':
      return te ? 'నిన్న ${t.count} బిల్లులు$money' : 'Yesterday: ${t.count} bills$money';
    case 'my_bills':
      return te ? '${t.count} బిల్లులు కట్టాలి$money' : '${t.count} bills to pay$money';
    case 'family':
      return te ? 'ఇంటి లిస్ట్‌లో ${t.count} వస్తువులు' : '${t.count} things on the home list';
    default:
      return te ? '${t.name}: మళ్ళీ అదేనా?' : '${t.name}: same again?';
  }
}

String askodoxBriefSub(AskodoxBriefTask t, bool te) {
  switch (t.key) {
    case 'dues':
      return te ? 'మెసేజ్ రెడీ · మీరు పంపితేనే వెళ్తుంది' : 'Message ready · goes only when you send it';
    case 'low_stock':
      return te ? 'సప్లయర్‌కి ఆర్డర్ డ్రాఫ్ట్ రెడీ' : 'Order draft for the supplier is ready';
    case 'winback':
      return te ? '${t.days} రోజులుగా · మెసేజ్ రెడీ' : 'For ${t.days} days · message ready';
    case 'yesterday':
      return te ? 'రోజు రిపోర్ట్' : 'Day report';
    case 'my_bills':
      return te ? 'మీ బిల్లులు' : 'Your bills';
    case 'family':
      return te ? 'ఇంకా కొనాలి' : 'Still to buy';
    default:
      return te ? 'ఒక్క టచ్‌తో అదే ఆర్డర్' : 'The same order in one touch';
  }
}

String askodoxBriefButton(AskodoxBriefTask t, bool te) {
  switch (t.action) {
    case 'send':
      return te ? 'పంపు' : 'Send';
    case 'approve':
      return te ? 'ఆమోదించు' : 'Approve';
    default:
      return te ? 'చూడు' : 'View';
  }
}

/// Yesterday's counts ASKODOX really did, in a fixed order; a count the server left out is not shown.
List<(String, int)> askodoxBriefHandled(Object? raw, bool te) {
  if (raw is! Map) return const [];
  const labels = {
    'bills': ('బిల్స్ సేవ్', 'Bills saved'),
    'reminders': ('బాకీ రిమైండర్లు', 'Due reminders'),
    'payments': ('పేమెంట్లు విన్నది', 'Payments heard'),
  };
  return [
    for (final entry in labels.entries)
      if (raw[entry.key] is num) (te ? entry.value.$1 : entry.value.$2, (raw[entry.key] as num).toInt()),
  ];
}
