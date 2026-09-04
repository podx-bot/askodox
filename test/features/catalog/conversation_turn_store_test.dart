import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/catalog/application/conversation_turn_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('persists and restores ASKODOX conversation turns', () async {
    const store = ConversationTurnStore();
    const turns = [
      ConversationTurnRecord(text: 'I need chicken nearby', isUser: true),
      ConversationTurnRecord(text: 'How much do you need?', isUser: false),
      ConversationTurnRecord(text: '5 kg', isUser: true),
    ];

    await store.save(turns);
    final restored = await store.load();

    expect(restored, hasLength(3));
    expect(restored[0].text, 'I need chicken nearby');
    expect(restored[0].isUser, isTrue);
    expect(restored[1].isUser, isFalse);
    expect(restored[2].text, '5 kg');
  });

  test('clear removes persisted conversation turns', () async {
    const store = ConversationTurnStore();
    await store.save(const [
      ConversationTurnRecord(text: 'Need a ride', isUser: true),
    ]);

    await store.clear();

    expect(await store.load(), isEmpty);
  });
}
