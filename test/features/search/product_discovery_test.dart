import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/catalog/domain/entities/brand.dart';
import 'package:podx/features/catalog/domain/entities/product.dart';
import 'package:podx/features/search/data/mock_product_discovery_repository.dart';
import 'package:podx/features/search/domain/search_models.dart';

void main() {
  const repository = MockProductDiscoveryRepository();
  const brand = Brand(id: 'soundcore', name: 'SoundCore', verified: true);
  const products = [Product(id: 'wave-headphones', name: 'Wave Wireless Headphones', description: '', price: 100, originalPrice: 120, icon: '🎧', categoryId: 'electronics', subcategoryId: 'audio', brand: brand, rating: 4, reviewCount: 1, inStock: true, tags: ['headphones', 'music'])];
  test('matches exact, synonym and similar spelling searches', () {
    expect(repository.matchText('headphones', products).single.kind, MatchKind.exact);
    expect(repository.matchText('earphones', products), isNotEmpty);
    expect(repository.matchText('headphons', products).single.kind, MatchKind.similarSpelling);
  });
  test('returns all barcode states', () {
    expect(repository.scanBarcode(const Barcode('abc'), products).state, BarcodeMatchState.invalid);
    expect(repository.scanBarcode(const Barcode('89010003'), products).state, BarcodeMatchState.found);
    expect(repository.scanBarcode(const Barcode('12345678'), products).state, BarcodeMatchState.notFound);
  });
  test('mock OCR and image adapters return catalog matches', () {
    expect(repository.extractMockText('gallery', products).matches, isNotEmpty);
    expect(repository.searchImage(const ImageSearchRequest(localReference: 'local://image'), products), isNotEmpty);
  });
}
