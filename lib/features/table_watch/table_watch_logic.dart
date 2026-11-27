/// Table watch (owner 2026-11-27, phase 5): what a table's state reads as. The states come from the server
/// (`pos_table_watch.py`): empty / seated / unseen / waiting / eating. QR only -- no camera.
library;

const askodoxTableWatchStates = ['empty', 'seated', 'unseen', 'waiting', 'eating'];

/// The word on the table's card.
String askodoxTableWatchText(String state, bool te) => switch (state) {
      'seated' => te ? 'కూర్చున్నారు' : 'Seated',
      'unseen' => te ? 'వెళ్ళి పలకరించాలి' : 'Go to them',
      'waiting' => te ? 'ఆర్డర్ వేచి' : 'Order waiting',
      'eating' => te ? 'తింటున్నారు' : 'Eating',
      _ => te ? 'ఖాళీ' : 'Free',
    };

/// "12m" / "1h 05m"; an empty table shows nothing.
String askodoxTableWatchTime(String state, int minutes) {
  if (state == 'empty' || !askodoxTableWatchStates.contains(state)) return '';
  final m = minutes < 0 ? 0 : minutes;
  if (m < 60) return '${m.toString().padLeft(2, '0')}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

/// The line of one alert: a table whose people sat and nobody has gone to them yet.
String askodoxTableWatchAlert(String table, int minutes, bool te) => te
    ? 'టేబుల్ $table · $minutes నిమిషాలుగా కూర్చున్నారు. వెళ్ళి ఆర్డర్ తీసుకోండి.'
    : 'Table $table · seated $minutes min. Go and take the order.';

/// Tables that need a person first: unseen, then the longest wait, then the rest as the server ordered them.
List<Map<String, Object?>> askodoxTableWatchOrder(List<Map<String, Object?>> tables) {
  int rank(Map<String, Object?> t) => switch ('${t['state']}') { 'unseen' => 0, 'waiting' => 1, 'seated' => 2, 'eating' => 3, _ => 4 };
  int minutes(Map<String, Object?> t) => t['minutes'] is num ? (t['minutes'] as num).toInt() : 0;
  final indexed = [for (var i = 0; i < tables.length; i++) (i, tables[i])];
  indexed.sort((a, b) {
    final byRank = rank(a.$2).compareTo(rank(b.$2));
    if (byRank != 0) return byRank;
    if (rank(a.$2) < 4) {
      final byWait = minutes(b.$2).compareTo(minutes(a.$2));
      if (byWait != 0) return byWait;
    }
    return a.$1.compareTo(b.$1);
  });
  return [for (final row in indexed) row.$2];
}
