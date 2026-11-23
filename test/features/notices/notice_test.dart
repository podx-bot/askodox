import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/notices/notice_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paise show as rupees with two places', () {
    expect(askodoxNoticeRupees(5), '₹0.05');
    expect(askodoxNoticeRupees(125), '₹1.25');
    expect(askodoxNoticeRupees(5000), '₹50.00');
  });

  test('the server reason is read from detail.code, else from the status', () {
    const body = '{"detail":{"code":"quiet_hours","message":"Send in the morning."}}';
    final answer = askodoxNoticeAnswerOf(
        const ApiError<Map<String, Object?>>(ApiFailure(ApiFailureType.server, statusCode: 409, cause: body)));
    expect(answer.ok, isFalse);
    expect(answer.code, 'quiet_hours');
    expect(answer.message, 'Send in the morning.');
    final credits = askodoxNoticeAnswerOf(
        const ApiError<Map<String, Object?>>(ApiFailure(ApiFailureType.server, statusCode: 402)));
    expect(credits.code, 'AI_CREDITS_LOW');
    expect(askodoxNoticeAnswerOf(const ApiSuccess<Map<String, Object?>>({'people': 4})).ok, isTrue);
  });

  test('every reason has words in both languages', () {
    for (final code in ['not_owner', 'no_location', 'nobody', 'quiet_hours', 'daily_limit', 'AI_CREDITS_LOW',
      'no_links', 'image', 'sign_in', 'network', 'anything']) {
      expect(askodoxNoticeReason(code, true), isNotEmpty);
      expect(askodoxNoticeReason(code, false), isNotEmpty);
    }
  });

  test('heading comes from the subject and the design prompt keeps the brand, never links', () {
    expect(askodoxNoticeHeading('Diwali offer\nbiryani 20% off'), 'Diwali offer');
    expect(askodoxNoticeHeading('x' * 80).length, 60);
    final prompt = askodoxNoticeDesignPrompt(subject: 'Sankranti chicken offer', shop: 'Ravi Stores', heading: '₹20 off');
    expect(prompt, contains('Ravi Stores'));
    expect(prompt, contains('ASKODOX'));
    expect(prompt, contains('No phone numbers'));
  });
}
