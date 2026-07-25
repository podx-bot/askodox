import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_catalog_repository.dart';
import '../domain/entities/catalog.dart';
import '../domain/entities/product.dart';
import '../domain/repositories/catalog_repository.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => const MockCatalogRepository());
final catalogProvider = FutureProvider<Catalog>((ref) => ref.watch(catalogRepositoryProvider).loadCatalog());

final searchQueryProvider = StateProvider.autoDispose<String>((ref) => '');
final selectedCategoryProvider = StateProvider.autoDispose<String?>((ref) => null);
final selectedSubcategoryProvider = StateProvider.autoDispose<String?>((ref) => null);

final filteredProductsProvider = Provider.autoDispose<AsyncValue<List<Product>>>((ref) {
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final category = ref.watch(selectedCategoryProvider);
  final subcategory = ref.watch(selectedSubcategoryProvider);
  return ref.watch(catalogProvider).whenData((catalog) => catalog.products.where((product) {
        final searchable = [product.name, product.brand.name, ...product.tags].join(' ').toLowerCase();
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
