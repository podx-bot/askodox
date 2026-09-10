import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_brain.dart';
import 'package:podx/features/deal_brain/domain/universal_deal.dart';
import 'package:podx/features/matching/data/demo_natural_match_catalog.dart';

void main() {
  const brain = UniversalDealBrain();

  UniversalDeal deal(String text, {String? subject, String? category}) =>
      brain.capture(text).copyWith(
        intent: DealIntent.buy,
        subject: subject,
        category: category,
        location: const DealLocation(label: 'Vijayawada'),
      );

  test('sandbox catalog is opt-in and never leaks when disabled', () {
    final request = deal('Need chicken', subject: 'chicken', category: 'fresh_food');
    expect(DemoNaturalMatchCatalog.forDeal(request), isEmpty);
  });

  test('investor product flow has multiple realistic seller choices', () {
    final request = deal('Need chicken', subject: 'chicken', category: 'fresh_food');
    final matches = DemoNaturalMatchCatalog.forDeal(request, enabled: true);

    expect(matches.length, greaterThanOrEqualTo(4));
    expect(matches.every((item) => item.id.startsWith('demo-chicken-')), isTrue);
    expect(matches.every((item) => item.providerId?.startsWith('demo-provider-') ?? false), isTrue);
    expect(matches.every((item) => item.distanceKm != null), isTrue);
    expect(matches.every((item) => item.trustScore != null), isTrue);
  });

  test('investor service flow returns multiple service providers', () {
    final request = deal('Need AC repair service', subject: 'ac repair', category: 'service');
    final matches = DemoNaturalMatchCatalog.forDeal(request, enabled: true);

    expect(matches.length, greaterThanOrEqualTo(4));
    expect(matches.first.title, contains('QuickFix'));
  });

  test('investor demo covers jobs rides parcel appointments and catering', () {
    final cases = <UniversalDeal>[
      deal('Need computer operator job', subject: 'job', category: 'job'),
      deal('Need ride to Bhimavaram', subject: 'ride', category: 'ride'),
      deal('Need parcel delivery', subject: 'parcel', category: 'delivery'),
      deal('Need salon appointment', subject: 'appointment', category: 'appointment'),
      deal('Need catering for function', subject: 'catering', category: 'service'),
    ];

    for (final request in cases) {
      final matches = DemoNaturalMatchCatalog.forDeal(request, enabled: true);
      expect(matches.length, greaterThanOrEqualTo(2), reason: request.rawText);
      expect(matches.every((item) => item.id.startsWith('demo-')), isTrue);
    }
  });

  test('generic retail sandbox has multiple local seller options', () {
    final request = deal('Need TV', subject: 'tv', category: 'product');
    final matches = DemoNaturalMatchCatalog.forDeal(request, enabled: true);

    expect(matches.length, greaterThanOrEqualTo(3));
    expect(matches.every((item) => item.subtitle?.contains('Sandbox') ?? false), isTrue);
  });
}
