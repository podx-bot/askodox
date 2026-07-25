import 'package:flutter/foundation.dart';

@immutable
class ProductSubcategory {
  const ProductSubcategory({required this.id, required this.name});

  final String id;
  final String name;

  factory ProductSubcategory.fromJson(Map<String, dynamic> json) =>
      ProductSubcategory(id: json['id'] as String, name: json['name'] as String);
}

@immutable
class ProductCategory {
  const ProductCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.subcategories,
  });

  final String id;
  final String name;
  final String icon;
  final List<ProductSubcategory> subcategories;

  factory ProductCategory.fromJson(Map<String, dynamic> json) => ProductCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String,
        subcategories: (json['subcategories'] as List<dynamic>)
            .map((item) => ProductSubcategory.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}
