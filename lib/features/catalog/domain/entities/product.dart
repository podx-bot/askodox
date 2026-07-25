import 'package:flutter/foundation.dart';

import 'brand.dart';

@immutable
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.originalPrice,
    required this.icon,
    required this.categoryId,
    required this.subcategoryId,
    required this.brand,
    required this.rating,
    required this.reviewCount,
    required this.inStock,
    required this.tags,
  });

  final String id;
  final String name;
  final String description;
  final double price;
  final double originalPrice;
  final String icon;
  final String categoryId;
  final String subcategoryId;
  final Brand brand;
  final double rating;
  final int reviewCount;
  final bool inStock;
  final List<String> tags;

  int get discountPercent =>
      originalPrice <= price ? 0 : ((originalPrice - price) / originalPrice * 100).round();

  factory Product.fromJson(Map<String, dynamic> json, Brand brand) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
        price: (json['price'] as num).toDouble(),
        originalPrice: (json['originalPrice'] as num).toDouble(),
        icon: json['icon'] as String,
        categoryId: json['categoryId'] as String,
        subcategoryId: json['subcategoryId'] as String,
        brand: brand,
        rating: (json['rating'] as num).toDouble(),
        reviewCount: json['reviewCount'] as int,
        inStock: json['inStock'] as bool,
        tags: List<String>.from(json['tags'] as List<dynamic>),
      );
}
