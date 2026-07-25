import 'dart:convert';

import 'package:flutter/services.dart';

import '../domain/entities/brand.dart';
import '../domain/entities/catalog.dart';
import '../domain/entities/category.dart';
import '../domain/entities/product.dart';
import '../domain/repositories/catalog_repository.dart';

class MockCatalogRepository implements CatalogRepository {
  const MockCatalogRepository();

  @override
  Future<Catalog> loadCatalog() async {
    final raw = await rootBundle.loadString('assets/mock/catalog.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final brands = (json['brands'] as List<dynamic>)
        .map((item) => Brand.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
    final brandById = {for (final brand in brands) brand.id: brand};
    return Catalog(
      brands: brands,
      categories: (json['categories'] as List<dynamic>)
          .map((item) => ProductCategory.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      products: (json['products'] as List<dynamic>).map((item) {
        final product = item as Map<String, dynamic>;
        return Product.fromJson(product, brandById[product['brandId']]!);
      }).toList(growable: false),
    );
  }
}
