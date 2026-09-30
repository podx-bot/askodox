import 'package:flutter_test/flutter_test.dart';

import 'package:podx/features/notifications/data/promotions_repository.dart';

void main() {
  test('promotion cards never become full-screen and keep the disclosure', () {
    final promo = AskodoxPromotion.fromJson({
      'delivery_id': 7,
      'title': 'Diwali sweets',
      'body': '20% off',
      'size': 'full',
      'image_url': 'http://insecure.example/x.png',
      'disclosure': 'Sponsored',
      'advertiser': 'Sri Sweets',
    })!;
    expect(promo.size, 'compact');
    expect(promo.imageUrl, isNull, reason: 'only https images');
    expect(promo.disclosure, 'Sponsored');
    expect(AskodoxPromotion.fromJson({'title': 'x'}), isNull);
  });
}
