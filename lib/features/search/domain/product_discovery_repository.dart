import '../../catalog/domain/entities/product.dart';
import 'search_models.dart';

/// Replace this contract with an ML Kit, Vision, Gemini, OpenAI or barcode SDK
/// adapter later. UI and application code remain vendor-independent.
abstract interface class ProductDiscoveryRepository {
  List<SmartMatch> matchText(String text, List<Product> catalog);
  BarcodeResult scanBarcode(Barcode barcode, List<Product> catalog);
  OCRResult extractMockText(String source, List<Product> catalog);
  List<SmartMatch> searchImage(ImageSearchRequest request, List<Product> catalog);
  List<SearchSuggestion> suggestions(List<String> recent);
  List<RelatedProduct> related(Product product, List<Product> catalog);
}
