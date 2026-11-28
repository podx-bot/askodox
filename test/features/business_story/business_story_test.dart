import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/config/theme/app_theme.dart';
import 'package:podx/features/business_story/business_story.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('encode / decode keeps answers and only known, short chips', () {
    const s = AskodoxStory(answers: ['a', 'b'], chips: {'type': 'Hotel', 'problem': 'Stock'});
    final back = askodoxStoryDecode(askodoxStoryEncode(s));
    expect(back.answers, ['a', 'b']);
    expect(back.chips, {'type': 'Hotel', 'problem': 'Stock'});
    expect(askodoxStoryDecode('not json').answers, isEmpty);
    expect(askodoxStoryDecode('{"c":{"other":"x","type":""}}').chips, isEmpty);
  });

  test('next question follows the answers; chip lead words', () {
    expect(const AskodoxStory().next, askodoxStoryQuestions[0]);
    expect(const AskodoxStory(answers: ['a', 'b', 'c']).next, isNull);
    expect(const AskodoxStory(answers: ['a', 'b']).words, 'a. b');
    expect(askodoxStoryChipText('problem', 'x', false), 'Problem: x');
    expect(askodoxStoryChipText('type', 'Hotel', true), 'Hotel');
  });

  testWidgets('first question shown with a mic and a typing box; saved chips can be removed', (tester) async {
    SharedPreferences.setMockInitialValues({
      askodoxBusinessStoryPrefsKey: askodoxStoryEncode(const AskodoxStory(answers: ['Hotel'], chips: {'type': 'Hotel'})),
    });
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(child: MaterialApp(theme: AppTheme.light, home: const AskodoxBusinessStoryScreen())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxStoryBubble-q1')), findsOneWidget);
    expect(find.byKey(const Key('askodoxStoryBubble-a0')), findsOneWidget);
    expect(find.byKey(const Key('askodoxStoryChip-type')), findsOneWidget);
    expect(find.byKey(const Key('askodoxStoryField')), findsOneWidget);
    await tester.tap(find.descendant(of: find.byKey(const Key('askodoxStoryChip-type')), matching: find.byIcon(Icons.cancel)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxStoryChip-type')), findsNothing);
  });
}
