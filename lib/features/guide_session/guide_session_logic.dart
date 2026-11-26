/// Guide session (owner 2026-11-26): pure rules, no Flutter. The questions themselves come from the server and follow
/// what the person says; only the topic names, the time choices and the "why we ask" words are fixed here.
library;

/// The minutes a person can pick. Any other number is fine too: "a little time" is never refused.
const askodoxGuideTimeChoices = <int>[5, 10, 30, 60];

/// (English, Telugu) of a server topic key.
const askodoxGuideTopicNames = <String, (String, String)>{
  'who': ('About you', 'మీ గురించి'),
  'work': ('Your work', 'మీ పని'),
  'wants': ('What you need from the app', 'యాప్ లో మీకు కావాల్సినవి'),
  'pages': ('Arranging your pages', 'మీ పేజీల అమరిక'),
  'team': ('Your team', 'మీ టీమ్'),
  'routine': ('Your day', 'మీ రోజు'),
  'things': ('Vehicles and things you own', 'మీ వాహనాలు, వస్తువులు'),
  'menu': ('Items and prices', 'వస్తువులు, ధరలు'),
  'photos': ('Photos, videos and links', 'ఫోటోలు, వీడియోలు, లింకులు'),
  'money': ('Earnings, loans and assets (only if you wish)', 'ఆదాయం, అప్పులు, ఆస్తులు (మీకు ఇష్టమైతే)'),
};

String askodoxGuideTopicName(String key, {required bool te}) {
  final n = askodoxGuideTopicNames[key];
  if (n == null) return key;
  return te ? n.$2 : n.$1;
}

/// The topic keys of a server list (`done` / `remaining` ...), as plain strings.
List<String> askodoxGuideKeys(Object? raw) => [
      if (raw is List)
        for (final v in raw)
          if (v is String) v else if (v is Map && v['key'] is String) v['key'] as String
    ];

/// True once the minutes the person gave have passed (the screen then OFFERS to stop; it never cuts them off).
bool askodoxGuideTimeUp(DateTime started, int minutes, DateTime now) => now.difference(started).inSeconds >= minutes * 60;

/// "10 నిమిషాలు" / "1 గంట" / "10 minutes" / "1 hour".
String askodoxGuideMinutesLabel(int minutes, {required bool te}) {
  if (minutes >= 60 && minutes % 60 == 0) {
    final h = minutes ~/ 60;
    return te ? '$h గంట${h > 1 ? 'లు' : ''}' : '$h hour${h > 1 ? 's' : ''}';
  }
  return te ? '$minutes నిమిషాలు' : '$minutes minutes';
}

/// Why the questions are asked, said before the person agrees. The same points the server enforces: kept only with
/// consent, never sold or given, deleted when asked, anything can be left out.
List<String> askodoxGuideWhyPoints({required bool te}) => te
    ? const [
        'రేపు మీరు చాట్ లో ఏదైనా అడిగినప్పుడు, ఈ వివరాలతో కలిపి మీ సొంత అసిస్టెంట్ లాగా సరైన సలహా ఇవ్వడానికి.',
        'మీ వివరాలు ఎవరికీ ఇవ్వము, అమ్మము. మీ యాప్ లో, మీకు సహాయం కోసమే.',
        'మీరు కోరితే డిలీట్ చేస్తాం. డిలీట్ చేస్తే మా డేటాబేస్ లో ఉండదు.',
        'అప్పులు, ఆస్తులు, ఆదాయం చెప్పాలనుకుంటే చెప్పొచ్చు. ఇష్టం లేనిది వదిలేయొచ్చు.',
      ]
    : const [
        'So that when you ask in chat tomorrow, I can match it with these details and advise you like your own assistant.',
        'Your details are never given or sold. They stay in your app, only to help you.',
        'If you ask, they are deleted, and then they are not in our database.',
        'Loans, assets and earnings only if you wish to tell. Anything you do not want to share can be left out.',
      ];

/// One reminder from the server (`ref`, `kind` setup | feature, `route`, `text`).
class AskodoxGuideReminder {
  const AskodoxGuideReminder(this.ref, this.kind, this.route, this.text);
  final String ref;
  final String kind;
  final String route;
  final String text;

  static AskodoxGuideReminder? from(Map<String, Object?> json) {
    final ref = '${json['ref'] ?? ''}';
    final route = '${json['route'] ?? ''}';
    if (ref.isEmpty || !route.startsWith('/')) return null;
    return AskodoxGuideReminder(ref, '${json['kind'] ?? ''}', route, '${json['text'] ?? ''}');
  }
}
