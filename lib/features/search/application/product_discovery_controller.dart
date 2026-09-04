import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../catalog/application/catalog_providers.dart';
import '../../deal_brain/application/universal_deal_controller.dart';
import '../data/mock_product_discovery_repository.dart';
import '../domain/product_discovery_repository.dart';
import '../domain/search_models.dart';

final productDiscoveryRepositoryProvider = Provider<ProductDiscoveryRepository>(
  (ref) => const MockProductDiscoveryRepository(),
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
    final catalog = (await ref.read(catalogProvider.future)).products;
    final result = repository.extractMockText(source, catalog);
    state = state.copyWith(
      ocrResult: result,
      matches: result.matches,
      analytics: _analytics(ocr: 1),
    );
  }

  Future<void> uploadImage({bool cropped = false}) async {
    final request = ImageSearchRequest(
      localReference: 'local://pending-product-image.jpg',
      cropped: cropped,
    );
    final catalog = (await ref.read(catalogProvider.future)).products;
    state = state.copyWith(
      imageRequest: request,
      matches: repository.searchImage(request, catalog),
      analytics: _analytics(image: 1),
    );
  }

  Future<void> startVoice() async {
    state = state.copyWith(
      voiceState: VoiceSearchState.listening,
      clearVoiceResult: true,
    );
    try {
      final result =
          await _deviceChannel.invokeMethod<String>('startVoiceSearch');
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

      // Voice and text enter the same ASKODOX Party A ↔ Party B brain first.
      ref.read(universalDealControllerProvider.notifier).start(spoken);

      // Product discovery is supplemental evidence only. A catalog load/search
      // failure must never discard a valid voice result or universal deal.
      try {
        await search(spoken);
      } catch (_) {
        // Keep the primary universal-deal flow alive without catalog evidence.
      }

      // Speaking is a real lifecycle state. Android completes this method only
      // when the acknowledgement finishes (or immediately reports unavailable).
      state = state.copyWith(
        voiceState: VoiceSearchState.speaking,
        voiceResult: spoken,
      );
      try {
        await _deviceChannel.invokeMethod<bool>('speakAcknowledgement');
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