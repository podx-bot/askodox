/// School / tuition / college register (owner 2026-11-28): the words the page shows for what the server (`pos_school.py`)
/// sends. Pure, so a test reads every key; a problem key the app does not know shows its own key, never a blank.
library;

int askodoxSchoolInt(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

/// The title of one problem group of "today", in the order the server sends them.
String askodoxSchoolProblemTitle(String key, bool te) {
  switch (key) {
    case 'unlisted_pickup':
      return te ? 'జాబితాలో లేనివారు పిల్లను తీసుకెళ్లారు' : 'Someone not on the list took a child';
    case 'health_follow_up':
      return te ? 'ఎలా ఉన్నారో అడగాల్సిన పిల్లలు' : 'Children to ask after';
    case 'absent_streak':
      return te ? 'వరుసగా రాని పిల్లలు' : 'Away for days in a row';
    case 'unmarked':
      return te ? 'హాజరు వేయని క్లాసులు' : 'Classes not marked';
    case 'absent_today':
      return te ? 'ఈరోజు రాని పిల్లలు' : 'Absent today';
    default:
      return key;
  }
}

/// One line for one person / class inside a problem group.
String askodoxSchoolItemText(String key, Map<String, Object?> item, bool te) {
  switch (key) {
    case 'unlisted_pickup':
      return '${item['student'] ?? ''} · ${item['who'] ?? ''}';
    case 'health_follow_up':
      return '${item['student'] ?? ''} · ${askodoxSchoolOutcomeText('${item['outcome'] ?? ''}', te)}';
    case 'absent_streak':
      final days = askodoxSchoolInt(item['days']);
      return '${item['name'] ?? ''} · ${te ? '$days రోజులు' : '$days days'}';
    case 'unmarked':
      final teacher = '${item['teacher'] ?? ''}';
      return '${item['name'] ?? ''}${teacher.isEmpty ? '' : ' · $teacher'}';
    default:
      return '${item['name'] ?? ''}';
  }
}

String askodoxSchoolOutcomeText(String outcome, bool te) {
  switch (outcome) {
    case 'home':
      return te ? 'ఇంటికి పంపాం' : 'Sent home';
    case 'hospital':
      return te ? 'హాస్పిటల్' : 'Hospital';
    default:
      return te ? 'హెల్త్ రూమ్ లో' : 'In the health room';
  }
}

String askodoxSchoolGateKindText(String kind, bool te) {
  switch (kind) {
    case 'early':
      return te ? 'ముందే వెళ్తున్నారు' : 'Leaving early';
    default:
      return te ? 'పికప్' : 'Pick-up';
  }
}

String askodoxSchoolSavedText(int present, int absent, bool te) =>
    te ? 'సేవ్ అయింది: $present వచ్చారు, $absent రాలేదు' : 'Saved: $present present, $absent absent';
