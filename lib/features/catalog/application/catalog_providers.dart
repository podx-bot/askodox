import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/backend_providers.dart';
import '../data/mock_catalog_repository.dart';
import '../domain/entities/catalog.dart';
import '../domain/entities/product.dart';
import '../domain/repositories/catalog_repository.dart';

final catalogRepositoryProvider = Provider<CatalogRepository?>((ref) {
  final config = ref.watch(appConfigProvider);
  // Never leak demo inventory into production/rest builds. A real REST catalog
  // repository can replace this provider once the backend catalog contract is
  // enabled; until then production intentionally renders an empty catalog.
  if (config.backendProvider.name == 'rest') return null;
  return const MockCatalogRepository();
});

final catalogProvider = FutureProvider<Catalog>((ref) async {
  final repository = ref.watch(catalogRepositoryProvider);
  if (repository == null) {
    return const Catalog(categories: [], brands: [], products: []);
  }
  return repository.loadCatalog();
});

final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');
final selectedCategoryProvider = StateProvider.autoDispose<String?>((ref) => null);
final selectedSubcategoryProvider = StateProvider.autoDispose<String?>((ref) => null);

final filteredProductsProvider = Provider.autoDispose<AsyncValue<List<Product>>>((ref) {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final category = ref.watch(selectedCategoryProvider);
  final subcategory = ref.watch(selectedSubcategoryProvider);
  return ref.watch(catalogProvider).whenData((catalog) => catalog.products.where((product) {
        final categoryName = catalog.categories.where((item) => item.id == product.categoryId).map((item) => item.name).join(' ');
        final subcategoryName = catalog.categories.expand((item) => item.subcategories).where((item) => item.id == product.subcategoryId).map((item) => item.name).join(' ');
        final searchable = [product.name, product.brand.name, categoryName, subcategoryName, ...product.tags].join(' ').toLowerCase();
        return (query.isEmpty || searchable.contains(query)) &&
            (category == null || product.categoryId == category) &&
            (subcategory == null || product.subcategoryId == subcategory);
      }).toList(growable: false));
});

final productByIdProvider = Provider.family<AsyncValue<Product?>, String>((ref, id) =>
    ref.watch(catalogProvider).whenData((catalog) {
      for (final product in catalog.products) {
        if (product.id == id) return product;
      }
      return null;
    }));
