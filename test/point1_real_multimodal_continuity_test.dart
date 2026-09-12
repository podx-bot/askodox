import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:podx/features/search/application/product_discovery_controller.dart';
import 'package:podx/services/multimodal_capture_service.dart';
import 'package:podx/services/vision_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeCaptureService extends MultimodalCaptureService {
  _FakeCaptureService() : super();

  final XFile fixture = XFile('/tmp/point1-phone.jpg');

  @override
  Future<XFile?> captureCamera() async => fixture;

  @override
  Future<XFile?> chooseGallery() async => fixture;
}

class _FakeVisionApiService extends VisionApiService {
  const _FakeVisionApiService() : super();

  @override
  Future<Map<String, dynamic>?> analyze({
    required XFile image,
    required String userText,
    required String language,
  }) async =>
      <String, dynamic>{
        'request_text': 'I want to buy a phone',
        'detected_subject': 'phone',
        'category_hint': 'mobile_phone',
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const deviceChannel = MethodChannel('com.askodox.app/device');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceChannel, null);
  });

  test('Point 1 text voice OCR and image keep one active deal context', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceChannel, (call) async {
      switch (call.method) {
        case 'startVoiceSearch':
          return 'I want to buy a phone';
        case 'speakAcknowledgement':
          return true;
        default:
          return null;
      }
    });

    final container = ProviderContainer(
      overrides: [
        multimodalCaptureServiceProvider.overrideWithValue(_FakeCaptureService()),
        visionApiServiceProvider.overrideWithValue(const _FakeVisionApiService()),
      ],
    );
    addTearDown(container.dispose);

    final dealController =
        container.read(universalDealControllerProvider.notifier);
    final discoveryController =
        container.read(productDiscoveryControllerProvider.notifier);

    // 1) Real text entry path creates the authoritative active deal.
    dealController.start('I want to buy a phone');
    dealController.applySelectedLocation(
      label: 'Vijayawada',
      latitude: 16.5062,
      longitude: 80.6480,
    );

    void expectSameActiveDeal() {
      final deal = container.read(universalDealControllerProvider).deal;
      expect(deal, isNotNull);
      expect(deal!.subject?.toLowerCase(), contains('phone'));
      expect(deal.location.label, 'Vijayawada');
      expect(deal.location.latitude, 16.5062);
      expect(deal.location.longitude, 80.6480);
    }

    expectSameActiveDeal();

    // 2) Real Flutter voice controller path -> native MethodChannel -> same deal.
    await discoveryController.startVoice();
    expectSameActiveDeal();

    // 3) Real OCR controller path -> media capture -> Vision API -> same deal.
    await discoveryController.runOcr('camera');
    expectSameActiveDeal();

    // 4) Real image controller path -> gallery capture -> Vision API -> same deal.
    await discoveryController.uploadImage();
    expectSameActiveDeal();

    // All modalities must leave exactly one authoritative session alive.
    final session = container.read(universalDealControllerProvider);
    expect(session.deal, isNotNull);
    expect(session.deal!.subject?.toLowerCase(), contains('phone'));
  });
}
