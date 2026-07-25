import '../../catalog/domain/entities/product.dart';

enum SearchIntentType { text, barcode, ocr, image, voice }
class SearchIntent { const SearchIntent({required this.type, required this.value}); final SearchIntentType type; final String value; }

class Barcode { const Barcode(this.value); final String value; bool get isValid => RegExp(r'^\d{8,14}$').hasMatch(value); }
enum BarcodeMatchState { found, multipleMatches, notFound, invalid }
class BarcodeResult { const BarcodeResult(this.state, this.matches); final BarcodeMatchState state; final List<Product> matches; }

class OCRResult { const OCRResult({required this.extractedText, required this.matches, this.source = 'camera'}); final String extractedText; final List<SmartMatch> matches; final String source; }
class ImageSearchRequest { const ImageSearchRequest({required this.localReference, this.cropped = false}); final String localReference; final bool cropped; }

enum SuggestionSource { recent, trending, watchlist, nearbyDemand, popularBrand }
class SearchSuggestion { const SearchSuggestion(this.label, this.source); final String label; final SuggestionSource source; }

enum MatchKind { exact, similarSpelling, brand, synonym, alternatePackSize, related }
class MatchConfidence { const MatchConfidence(this.score); final double score; String get label => score >= .85 ? 'High' : score >= .6 ? 'Medium' : 'Low'; }
class SmartMatch { const SmartMatch({required this.product, required this.kind, required this.confidence, required this.reason}); final Product product; final MatchKind kind; final MatchConfidence confidence; final String reason; }
enum RelatedProductType { similar, alternateBrand, betterOffer, alternatePackSize }
class RelatedProduct { const RelatedProduct(this.product, this.type); final Product product; final RelatedProductType type; }

enum VoiceSearchState { idle, listening, processing, result, error }
class SearchAnalytics { const SearchAnalytics({this.mostSearched = const {}, this.failedSearches = const [], this.barcodeSearches = 0, this.ocrSearches = 0, this.imageSearches = 0}); final Map<String, int> mostSearched; final List<String> failedSearches; final int barcodeSearches, ocrSearches, imageSearches; }
