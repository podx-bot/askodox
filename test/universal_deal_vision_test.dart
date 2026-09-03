import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('vision hints fill missing deal fields without replacing known values', () async {
    final controller = UniversalDealController();
    controller.start('buy nearby');

    expect(controller.state.deal?.subject, isNull);
    expect(controller.state.deal?.category, 'product');

    controller.attachMedia(path: '/tmp/shoes.jpg', name: 'shoes.jpg');
    var attachment = controller.state.deal?.dynamicFields['attachment'] as Map;
    expect(attachment['analysisStatus'], 'analyzing');

    controller.mergeVisionAnalysis({
      'detected_subject': 'running shoes',
      'category_hint': 'fashion',
      'summary': 'A pair of running shoes is visible.',
      'deal_hints': {
        'subject': 'running shoes',
        'category': 'footwear',
        'variant': 'blue',
        'size': '9',
        'model': null,
        'quality': null,
      },
    });

    final deal = controller.state.deal!;
    expect(deal.subject, 'running shoes');
    expect(deal.category, 'product');
    expect(deal.variant, 'blue');
    expect(deal.size, '9');
    expect(deal.dynamicFields['visionAnalysis'], isA<Map>());
    attachment = deal.dynamicFields['attachment'] as Map;
    expect(attachment['analysisStatus'], 'ready');

    controller.dispose();
  });

  test('failed vision analysis keeps attachment and marks it failed', () async {
    final controller = UniversalDealController();
    controller.start('find this nearby');
    controller.attachMedia(path: '/tmp/item.jpg', name: 'item.jpg');

    var attachment = controller.state.deal?.dynamicFields['attachment'] as Map;
    expect(attachment['path'], '/tmp/item.jpg');
    expect(attachment['analysisStatus'], 'analyzing');

    controller.markVisionAnalysisFailed();

    attachment = controller.state.deal?.dynamicFields['attachment'] as Map;
    expect(attachment['path'], '/tmp/item.jpg');
    expect(attachment['name'], 'item.jpg');
    expect(attachment['analysisStatus'], 'failed');

    controller.dispose();
  });
}
