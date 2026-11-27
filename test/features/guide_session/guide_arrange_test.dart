import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/guide_session/guide_arrange.dart';
import 'package:podx/features/money_home/launcher_layout.dart';

AskodoxLaunchLayout _layout() => const AskodoxLaunchLayout([
      AskodoxLaunchEntry.page('s.bill'),
      AskodoxLaunchEntry.page('s.orders'),
      AskodoxLaunchEntry.folder('u1', 'Mine', ['s.dues', 's.day']),
      AskodoxLaunchEntry.page('s.link'),
      AskodoxLaunchEntry.page('s.team'),
    ], hidden: {'s.reports'});

void main() {
  test('named pages move to the front in the server order', () {
    final out = askodoxBringFirst(_layout(), ['s.link', 's.team']);
    expect([for (final e in out.entries) e.id].take(3), ['s.link', 's.team', 's.bill']);
  });

  test('folders, hidden and unknown pages are left alone; nothing is hidden or grouped', () {
    final before = _layout();
    final out = askodoxBringFirst(before, ['s.dues', 's.reports', 's.nope', 's.link']);
    expect(out.hidden, before.hidden);
    expect(out.entries.length, before.entries.length);
    expect(out.entry('f:u1')!.children, ['s.dues', 's.day']);
    expect(out.entries.first.id, 's.link');
    expect(out.placed, before.placed);
  });

  test('nothing to move gives back the same screen', () {
    final before = _layout();
    expect(askodoxBringFirst(before, const []).encode(), before.encode());
    expect(askodoxBringFirst(before, ['s.bill']).encode(), before.encode());
  });
}
