import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

void main() {
  test('registered rows carry why + fit status from the backend (round-trip)', () {
    final m = UniversalMatch.fromJson({
      'id': '7', 'title': 'Walking shoes', 'source': 'local',
      'why': 'Matches size 9, price ₹1,799 (under ₹2,000)', 'fit': {'status': 'fits'},
    });
    expect(m.why, startsWith('Matches size 9'));
    expect(m.fitStatus, 'fits');
    final again = UniversalMatch.fromJson(m.toJson());
    expect(again.why, m.why);
    expect(again.fitStatus, 'fits');
    expect(UniversalMatch.fromJson({'id': '8', 'title': 'x', 'source': 'online'}).why, isNull);
  });
}
