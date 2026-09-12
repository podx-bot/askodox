import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:podx/features/catalog/application/catalog_providers.dart';
import 'package:podx/features/deal_brain/application/universal_deal_controller.dart';
import 'package:podx/features/search/application/product_discovery_controller.dart';
import 'package:podx/services/multimodal_capture_service.dart';
import 'package:podx/services/vision_api_service.dart';

class _FakeCaptureService extends MultimodalCaptureService {
  @override
  Future<XFile?> chooseGallery() async => XFile.fromData(
        Uint8List.fromList(const <int>[1, 2, 3]),
        name: 'point1.jpg',
        mimeType: 'image/jpeg',
      );
}

class _FakeVisionApiService extends VisionApiService {
  const _FakeVisionApiService();

  @override
  Future<Map<String, dynamic>?> analyze({
    required XFile image,
    required String userText,
    required String language,
  }) async =>
      <String, dynamic>{
        'request_text': 'I want to buy a phone',
        'subject': 'phone',
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const deviceChannel = MethodChannel('com.askodox.app/device');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceChannel, (call) async {
      if (call.method == 'startVoiceSearch') {
        return 'I want to buy a phone';
      }
      if (call.method == 'speakAcknowledgement') return true;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(deviceChannel, null);
  });

  test('text voice and OCR pipelines preserve one active deal context', () async {
    final container = ProviderContainer(
      overrides: [
        catalogRepositoryProvider.overrideWithValue(null),
        multimodalCaptureServiceProvider.overrideWithValue(_FakeCaptureService()),
        visionApiServiceProvider.overrideWithValue(const _FakeVisionApiService()),
      ],
    );
    addTearDown(container.dispose);

    final dealController = container.read(universalDealControllerProvider.notifier);
    dealController.start('I want to buy a phone');
    dealController.applySelectedLocation(
      label: 'Vijayawada',
      latitude: 16.5062,
      longitude: 80.6480,
    );

    expect(container.read(universalDealControllerProvider).deal?.subject?.toLowerCase(), contains('phone'));
    expect(container.read(universalDealControllerProvider).deal?.location.label, 'Vijayawada');

    final discovery = container.read(productDiscoveryControllerProvider.notifier);

    await discovery.startVoice();
    final afterVoice = container.read(universalDealControllerProvider).deal;
    expect(afterVoice, isNotNull);
    expect(afterVoice!.subject?.toLowerCase(), contains('phone'));
    expect(afterVoice.location.label, 'Vijayawada');
    expect(afterVoice.location.latitude, 16.5062);
    expect(afterVoice.location.longitude, 80.6480);

    await discovery.runOcr('gallery');
    final afterOcr = container.read(universalDealControllerProvider).deal;
    expect(afterOcr, isNotNull);
    expect(afterOcr!.subject?.toLowerCase(), contains('phone'));
    expect(afterOcr.location.label, 'Vijayawada');
    expect(afterOcr.location.latitude, 16.5062);
    expect(afterOcr.location.longitude, 80.6480);

    expect(container.read(productDiscoveryControllerProvider).voiceResult, 'I want to buy a phone');
    expect(container.read(productDiscoveryControllerProvider).ocrResult?.extractedText, 'I want to buy a phone');
  });
}
