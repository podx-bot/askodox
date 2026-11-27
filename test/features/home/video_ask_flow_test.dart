import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/data/askodox_video_service.dart';

void main() {
  test('an unanswered study question carries next_step and offers the uploader', () {
    final a = AskodoxVideoAnswer.fromJson({
      'found': false,
      'answer': 'Not confirmed in this video.',
      'next_step': 'ask_uploader',
      'ask_uploader': true,
    });
    expect(a.found, isFalse);
    expect(a.nextStep, 'ask_uploader');
    expect(a.askUploader, isTrue);
  });

  test('an answered question never offers the uploader', () {
    final a = AskodoxVideoAnswer.fromJson({
      'found': true,
      'answer': 'The seller asks Rs 12.5 lakh.',
      'next_step': 'answered',
      'ask_uploader': false,
    });
    expect(a.nextStep, 'answered');
    expect(a.askUploader, isFalse);
  });

  test('an answer without the new fields reads as no uploader offer', () {
    final a = AskodoxVideoAnswer.fromJson({'found': false, 'answer': 'x'});
    expect(a.nextStep, isNull);
    expect(a.askUploader, isFalse);
  });

  test('only an auto-answer with text counts as answered; a waiting question does not', () {
    expect(const AskodoxUploaderMessage(status: 'AUTO_ANSWERED', reply: 'Yes, 2 days').answered, isTrue);
    expect(const AskodoxUploaderMessage(status: 'AUTO_ANSWERED', reply: '').answered, isFalse);
    expect(const AskodoxUploaderMessage(status: 'WAITING_FOR_OWNER').answered, isFalse);
  });
}
