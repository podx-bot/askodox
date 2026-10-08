import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/home/domain/result_board.dart';

void main() {
  group('Result Board lifecycle', () {
    test('every state from the screen facts', () {
      expect(askodoxBoardStateOf(hasDeck: false, retired: false, minimized: false), AskodoxBoardState.hidden);
      expect(askodoxBoardStateOf(hasDeck: true, retired: false, minimized: false), AskodoxBoardState.expanded);
      expect(askodoxBoardStateOf(hasDeck: true, retired: false, minimized: true), AskodoxBoardState.minimized);
      expect(askodoxBoardStateOf(hasDeck: true, retired: false, minimized: false, refreshing: true),
          AskodoxBoardState.loading);
      expect(askodoxBoardStateOf(hasDeck: true, retired: false, minimized: false, outdated: true),
          AskodoxBoardState.stale);
      expect(askodoxBoardStateOf(hasDeck: true, retired: true, minimized: true), AskodoxBoardState.archived,
          reason: 'a retired deck is archived even if it had been minimized');
    });
  });

  group('Result Board sizing (Android screens)', () {
    // Height left for the Home column on common phones (header + nav already
    // removed), with and without the keyboard.
    for (final available in const [420.0, 520.0, 640.0, 760.0, 900.0]) {
      for (final keyboard in const [false, true]) {
        test('available $available keyboard $keyboard: conversation + input keep their room', () {
          final height = askodoxBoardMaxHeight(available, keyboard: keyboard, expanded: true);
          if (height == null) return; // the pill is shown instead
          expect(height, greaterThanOrEqualTo(askodoxBoardMinimum));
          expect(available - height, greaterThanOrEqualTo(askodoxComposerReserve + askodoxConversationMinimum));
          expect(height, lessThanOrEqualTo(available * .44));
        });
      }
    }

    test('no room for a useful board -> null (show the pill)', () {
      expect(askodoxBoardMaxHeight(300, keyboard: true), isNull);
      expect(askodoxBoardMaxHeight(0, keyboard: false), isNull);
      expect(askodoxBoardMaxHeight(double.infinity, keyboard: false), isNull);
      expect(askodoxBoardMaxHeight(640, keyboard: false), isNotNull);
    });
  });

  group('reasoning before results', () {
    test('guidance phrasing is not a results claim', () {
      for (final text in [
        'Here is a rough cost breakdown for 110 sq ft.',
        'Here is what matters most: warranty and delivery.',
        'If you are searching for durable tiles, check the PEI rating.',
        'Here are the key points: wastage and finish.',
        'Here are a few tips before you buy.',
      ]) {
        expect(askodoxReplyClaimsResults(text), isFalse, reason: text);
      }
      for (final text in ['Here are some options nearby.', 'Showing tiles near you.', 'Let me find shops for you.',
          'ఇవి ఉన్నాయి']) {
        expect(askodoxReplyClaimsResults(text), isTrue, reason: text);
      }
    });

    test('only the false claim is removed; the estimate and question stay', () {
      const reply = 'For 100 sq ft plan about 110 sq ft (estimate). Here are some options nearby.\n\n'
          'Do you need floor or wall tiles?';
      final kept = askodoxStripResultClaims(reply);
      expect(kept, contains('110 sq ft'));
      expect(kept, contains('floor or wall tiles?'));
      expect(kept, isNot(contains('Here are some options')));
      expect(askodoxStripResultClaims('Showing tiles near you.'), isEmpty);
    });

    test('the brain answer keeps everything but its trailing question', () {
      expect(askodoxWithoutTrailingQuestion('About ₹12,000 total (estimate).\nWhich room is it for?'),
          'About ₹12,000 total (estimate).');
      expect(askodoxWithoutTrailingQuestion('Which room?'), isEmpty);
      expect(askodoxWithoutTrailingQuestion('No question here.'), 'No question here.');
    });
  });
}
