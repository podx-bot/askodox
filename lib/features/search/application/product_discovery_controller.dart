import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../../services/multimodal_capture_service.dart';
import '../../../services/vision_api_service.dart';
import '../../catalog/application/catalog_providers.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../data/mock_product_discovery_repository.dart';
import '../domain/product_discovery_repository.dart';
import '../domain/search_models.dart';

final productDiscoveryRepositoryProvider = Provider<ProductDiscoveryRepository>(
  (ref) => const MockProductDiscoveryRepository(),
);

final multimodalCaptureServiceProvider = Provider<MultimodalCaptureService>(
  (ref) => MultimodalCaptureService(),
);

final visionApiServiceProvider = Provider<VisionApiService>(
  (ref) => const VisionApiService(),
);

class DiscoveryState {
  const DiscoveryState({
    this.matches = const [],
    this.barcodeResult,
    this.ocrResult,
    this.imageRequest,
    this.voiceState = VoiceSearchState.idle,
    this.voiceResult,
    this.barcodeHistory = const [],
    this.analytics = const SearchAnalytics(),
  });

  final List<SmartMatch> matches;
  final BarcodeResult? barcodeResult;
  final OCRResult? ocrResult;
  final ImageSearchRequest? imageRequest;
  final VoiceSearchState voiceState;
  final String? voiceResult;
  final List<String> barcodeHistory;
  final SearchAnalytics analytics;

  DiscoveryState copyWith({
    List<SmartMatch>? matches,
    BarcodeResult? barcodeResult,
    OCRResult? ocrResult,
    ImageSearchRequest? imageRequest,
    VoiceSearchState? voiceState,
    String? voiceResult,
    bool clearVoiceResult = false,
    List<String>? barcodeHistory,
    SearchAnalytics? analytics,
  }) =>
      DiscoveryState(
        matches: matches ?? this.matches,
        barcodeResult: barcodeResult ?? this.barcodeResult,
        ocrResult: ocrResult ?? this.ocrResult,
        imageRequest: imageRequest ?? this.imageRequest,
        voiceState: voiceState ?? this.voiceState,
        voiceResult: clearVoiceResult ? null : (voiceResult ?? this.voiceResult),
        barcodeHistory: barcodeHistory ?? this.barcodeHistory,
        analytics: analytics ?? this.analytics,
      );
}

final productDiscoveryControllerProvider =
    StateNotifierProvider<ProductDiscoveryController, DiscoveryState>(
  (ref) => ProductDiscoveryController(
    ref,
    ref.watch(productDiscoveryRepositoryProvider),
  ),
);

class ProductDiscoveryController extends StateNotifier<DiscoveryState> {
  ProductDiscoveryController(this.ref, this.repository)
      : super(const DiscoveryState());

  final Ref ref;
  final ProductDiscoveryRepository repository;
  static const _deviceChannel = MethodChannel('com.askodox.app/device');

  Future<void> search(String query) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    final catalog = (await ref.read(catalogProvider.future)).products;
    final matches = repository.matchText(normalized, catalog);
    final counts = {...state.analytics.mostSearched};
    counts[normalized] = (counts[normalized] ?? 0) + 1;
    state = state.copyWith(
      matches: matches,
      analytics: SearchAnalytics(
        mostSearched: counts,
        failedSearches: matches.isEmpty
            ? [...state.analytics.failedSearches, normalized]
            : state.analytics.failedSearches,
        barcodeSearches: state.analytics.barcodeSearches,
        ocrSearches: state.analytics.ocrSearches,
        imageSearches: state.analytics.imageSearches,
      ),
    );
  }

  Future<void> scan(String value) async {
    final catalog = (await ref.read(catalogProvider.future)).products;
    final result = repository.scanBarcode(Barcode(value.trim()), catalog);
    state = state.copyWith(
      barcodeResult: result,
      barcodeHistory: [
        value.trim(),
        ...state.barcodeHistory.where((e) => e != value.trim()),
      ].take(8).toList(),
      matches: result.matches
          .map(
            (p) => SmartMatch(
              product: p,
              kind: MatchKind.exact,
              confidence: const MatchConfidence(.99),
              reason: 'Barcode match',
            ),
          )
          .toList(),
      analytics: _analytics(barcode: 1),
    );
  }

  Future<void> runOcr(String source) async {
    final capture = ref.read(multimodalCaptureServiceProvider);
    final image = source.toLowerCase().contains('camera')
        ? await capture.captureCamera()
        : await capture.chooseGallery();
    if (image == null) return;

    final settings = ref.read(appSettingsProvider);
    final language = settings.locale?.languageCode ?? 'en';
    final analysis = await ref.read(visionApiServiceProvider).analyze(
          image: image,
          userText: 'Read the useful text and understand what I need from this image.',
          language: language,
        );
    if (analysis == null) return;

    final extracted = _visionText(analysis);
    if (extracted.isEmpty) return;

    ref.read(universalDealControllerProvider.notifier).start(extracted);

    final catalog = (await ref.read(catalogProvider.future)).products;
    final matches = repository.matchText(extracted, catalog);
    state = state.copyWith(
      ocrResult: OCRResult(
        extractedText: extracted,
        matches: matches,
        source: source,
      ),
      matches: matches,
      analytics: _analytics(ocr: 1),
    );
  }

  Future<void> uploadImage({bool cropped = false}) async {
    final capture = ref.read(multimodalCaptureServiceProvider);
    final image = await capture.chooseGallery();
    if (image == null) return;

    final settings = ref.read(appSettingsProvider);
    final language = settings.locale?.languageCode ?? 'en';
    final analysis = await ref.read(visionApiServiceProvider).analyze(
          image: image,
          userText: 'Understand this image and identify the user request or useful details.',
          language: language,
        );
    if (analysis == null) return;

    final extracted = _visionText(analysis);
    if (extracted.isNotEmpty) {
      ref.read(universalDealControllerProvider.notifier).start(extracted);
    }

    final request = ImageSearchRequest(
      localReference: image.path,
      cropped: cropped,
    );
    final catalog = (await ref.read(catalogProvider.future)).products;
    final matches = extracted.isEmpty
        ? repository.searchImage(request, catalog)
        : repository.matchText(extracted, catalog);
    state = state.copyWith(
      imageRequest: request,
      matches: matches,
      analytics: _analytics(image: 1),
    );
  }

  String _visionText(Map<String, dynamic> analysis) {
    for (final key in const ['request_text', 'text', 'summary', 'description']) {
      final value = analysis[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    final labels = analysis['labels'];
    if (labels is List) {
      return labels
          .whereType<String>()
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' ');
    }
    return '';
  }

  Future<void> startVoice() async {
    final appSettings = ref.read(appSettingsProvider);
    final languageCode = appSettings.locale?.languageCode;
    final recognitionArguments = <String, Object?>{
      if (languageCode != null) 'languageCode': languageCode,
    };
    final ttsArguments = <String, Object?>{
      ...recognitionArguments,
      'voicePreference': appSettings.voicePreference.storageValue,
    };

    state = state.copyWith(
      voiceState: VoiceSearchState.listening,
      clearVoiceResult: true,
    );
    try {
      final result = await _deviceChannel.invokeMethod<String>(
        'startVoiceSearch',
        recognitionArguments,
      );
      final spoken = result?.trim();
      if (spoken == null || spoken.isEmpty) {
        state = state.copyWith(
          voiceState: VoiceSearchState.idle,
          clearVoiceResult: true,
        );
        return;
      }

      state = state.copyWith(
        voiceState: VoiceSearchState.processing,
        voiceResult: spoken,
      );

      ref.read(universalDealControllerProvider.notifier).start(spoken);

      try {
        await search(spoken);
      } catch (_) {
        // Keep the primary universal-deal flow alive without catalog evidence.
      }

      state = state.copyWith(
        voiceState: VoiceSearchState.speaking,
        voiceResult: spoken,
      );
      try {
        await _deviceChannel.invokeMethod<bool>(
          'speakAcknowledgement',
          ttsArguments,
        );
      } catch (_) {
        // TTS is helpful feedback, not a blocker for the user's request.
      }

      state = state.copyWith(
        voiceState: VoiceSearchState.result,
        voiceResult: spoken,
      );
    } on PlatformException catch (error) {
      state = state.copyWith(
        voiceState: VoiceSearchState.idle,
        voiceResult: error.message ?? 'Voice search unavailable',
      );
    } catch (_) {
      state = state.copyWith(
        voiceState: VoiceSearchState.idle,
        voiceResult: 'Voice search unavailable',
      );
    }
  }

  SearchAnalytics _analytics({
    int barcode = 0,
    int ocr = 0,
    int image = 0,
  }) =>
      SearchAnalytics(
        mostSearched: state.analytics.mostSearched,
        failedSearches: state.analytics.failedSearches,
        barcodeSearches: state.analytics.barcodeSearches + barcode,
        ocrSearches: state.analytics.ocrSearches + ocr,
        imageSearches: state.analytics.imageSearches + image,
      );
}
