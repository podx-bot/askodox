import 'package:flutter/foundation.dart';

@immutable
class Product {
  const Product({
    required this.name,
    required this.shop,
    required this.price,
    required this.icon,
  });

  final String name;
  final String shop;
  final double price;
  final String icon;
}
