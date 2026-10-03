import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/home/presentation/video_viewer_screen.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';

void main() {
  test('advisor block parses the open question, readiness and guidance', () {
    final view = AskodoxAdvisorView.fromJson({
      'ready': false,
      'questions': [
        {'field': 'budget', 'question': 'మీ బడ్జెట్ ఎంత?', 'required': true, 'choices': []}
      ],
      'guidance': [
        {'advice': 'For standing all day, comfort matters.', 'high_stakes': false},
        {'advice': 'No approval is guaranteed.', 'high_stakes': true},
      ],
    })!;
    expect(view.ready, isFalse);
    expect(view.field, 'budget');
    expect(view.question, 'మీ బడ్జెట్ ఎంత?');
    expect(view.guidance, hasLength(2));
    expect(view.highStakes, isTrue);
    expect(AskodoxAdvisorView.fromJson(null), isNull);
  });

  test('results wait only for a REQUIRED question, never when the user asked to see them', () {
    const held = AskodoxAdvisorView(ready: false, field: 'budget', question: 'Budget?', required: true);
    expect(askodoxAdvisorHolds(held, showNow: false, videoAsk: false), isTrue);
    expect(askodoxAdvisorHolds(held, showNow: true, videoAsk: false), isFalse);
    expect(askodoxAdvisorHolds(held, showNow: false, videoAsk: true), isFalse);
    const optional = AskodoxAdvisorView(ready: true, field: 'usage', question: 'Usage?');
    expect(askodoxAdvisorHolds(optional, showNow: false, videoAsk: false), isFalse);
  });

  test('no-preference replies in English, Telugu and Hindi', () {
    for (final t in ['any', 'Any brand', 'no preference', 'ఏదైనా', 'ఏదైనా సరే', 'कोई भी', 'any.']) {
      expect(askodoxIsNoPreference(t), isTrue, reason: t);
    }
    for (final t in ['Nike', '2000', 'any shoes under 2000', 'size 9']) {
      expect(askodoxIsNoPreference(t), isFalse, reason: t);
    }
  });

  test('named result groups are remembered (videos / reviews / deals)', () {
    expect(askodoxRequestedGroups('show me shoe reviews and deals'), ['videos', 'deals']);
    expect(askodoxRequestedGroups('TV వీడియోలు'), ['videos']);
    expect(askodoxRequestedGroups('2000'), isEmpty);
  });

  test('YouTube embeds identify ASKODOX (Error 153) and other players are untouched', () {
    final yt = askodoxEmbedWithOrigin(Uri.parse('https://www.youtube-nocookie.com/embed/abc123def45?playsinline=1'));
    expect(yt.queryParameters['origin'], 'https://askodox.com');
    expect(yt.queryParameters['widget_referrer'], 'https://askodox.com');
    expect(yt.queryParameters['playsinline'], '1');
    expect(askodoxEmbedHeaders(yt), {'Referer': 'https://askodox.com/'});
    final other = Uri.parse('https://player.vimeo.com/video/1');
    expect(askodoxEmbedWithOrigin(other), other);
    expect(askodoxEmbedHeaders(other), isEmpty);
  });

  test('video next steps never search the raw video title', () {
    const titleOnly = UniversalMatch(id: 'video-1', title: 'ఈ కారు చూడండి!!! 🔥', source: 'video');
    expect(askodoxVideoNextSteps(titleOnly), isEmpty);
    const linked = UniversalMatch(id: 'video-2', title: 'x', source: 'video', relatedProducts: ['Innova Crysta']);
    final steps = askodoxVideoNextSteps(linked);
    expect(steps.map((s) => s.ask), everyElement(contains('Innova Crysta')));
  });
}
