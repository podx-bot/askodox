import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/shared/widgets/chat_pins.dart';
import 'package:shared_preferences/shared_preferences.dart';

AskodoxChatPin _pin(String id) => AskodoxChatPin(id: id, route: '/$id', en: id, te: id);

void main() {
  test('at most three pins; a fourth replaces the chosen one; pins are links by key id (owner 2026-11-19)', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final pins = container.read(askodoxChatPinsProvider.notifier);
    await Future<void>.delayed(Duration.zero);
    pins.pin(_pin('a'));
    pins.pin(_pin('b'));
    pins.pin(_pin('c'));
    pins.pin(_pin('d')); // no room, nothing named to replace -> ignored
    expect([for (final p in container.read(askodoxChatPinsProvider).pins) p.id], ['a', 'b', 'c']);
    pins.pin(_pin('d'), replace: 'b');
    expect([for (final p in container.read(askodoxChatPinsProvider).pins) p.id], ['a', 'c', 'd']);
    pins.pin(_pin('a')); // pinning again does not duplicate
    expect(container.read(askodoxChatPinsProvider).pins.where((p) => p.id == 'a').length, 1);
    pins.unpin('c');
    pins.setFolded(true);
    expect(container.read(askodoxChatPinsProvider).folded, isTrue);
    expect(AskodoxChatPin.fromJson({'id': 'x', 'route': 'http://evil'}), isNull, reason: 'only in-app routes');
  });
}
