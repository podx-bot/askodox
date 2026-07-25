import 'package:flutter/foundation.dart';

@immutable
class ShopProfile {
  const ShopProfile({
    required this.shopName,
    required this.ownerName,
    required this.mobile,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.photoPath,
    required this.category,
  });

  final String shopName;
  final String ownerName;
  final String mobile;
  final String address;
  final double latitude;
  final double longitude;
  final String photoPath;
  final String category;
}

@immutable
class SellerProduct {
  const SellerProduct({
    required this.id,
    required this.catalogId,
    required this.name,
    required this.icon,
    required this.price,
    required this.stock,
  });

  final String id;
  final String catalogId;
  final String name;
  final String icon;
  final double price;
  final int stock;

  bool get isActive => stock > 0;

  SellerProduct copyWith({double? price, int? stock}) => SellerProduct(
        id: id,
        catalogId: catalogId,
        name: name,
        icon: icon,
        price: price ?? this.price,
        stock: stock ?? this.stock,
      );
}

@immutable
class SellerState {
  const SellerState({
    this.mobile = '',
    this.isOtpSent = false,
    this.isAuthenticated = false,
    this.profile,
    this.products = const [],
    this.pendingRequests = 3,
  });

  final String mobile;
  final bool isOtpSent;
  final bool isAuthenticated;
  final ShopProfile? profile;
  final List<SellerProduct> products;
  final int pendingRequests;

  SellerState copyWith({
    String? mobile,
    bool? isOtpSent,
    bool? isAuthenticated,
    ShopProfile? profile,
    List<SellerProduct>? products,
  }) =>
      SellerState(
        mobile: mobile ?? this.mobile,
        isOtpSent: isOtpSent ?? this.isOtpSent,
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        profile: profile ?? this.profile,
        products: products ?? this.products,
        pendingRequests: pendingRequests,
      );
}
