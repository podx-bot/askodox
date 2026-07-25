import 'package:flutter/foundation.dart';

enum VerificationStatus { pending, approved, rejected, suspended }

enum StockStatus { inStock, lowStock, outOfStock }

@immutable
class Shop {
  const Shop({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.photoPath,
    this.businessIdPath,
  });

  final String id;
  final String name;
  final String category;
  final String address;
  final double latitude;
  final double longitude;
  final String? photoPath;
  final String? businessIdPath;
}

@immutable
class Seller {
  const Seller({
    required this.id,
    required this.mobile,
    required this.ownerName,
    required this.shop,
    this.verificationStatus = VerificationStatus.pending,
    this.trustScore,
  });

  final String id;
  final String mobile;
  final String ownerName;
  final Shop shop;
  final VerificationStatus verificationStatus;
  final double? trustScore;
}

@immutable
class SellerProduct {
  const SellerProduct({
    required this.id,
    required this.catalogId,
    required this.name,
    required this.icon,
    required this.price,
    required this.stockStatus,
    required this.quantity,
    this.offerPrice,
    this.offerStart,
    this.offerExpiry,
    this.lastPriceUpdate,
  });

  final String id;
  final String catalogId;
  final String name;
  final String icon;
  final double price;
  final StockStatus stockStatus;
  final int quantity;
  final double? offerPrice;
  final DateTime? offerStart;
  final DateTime? offerExpiry;
  final DateTime? lastPriceUpdate;

  bool get isActive => stockStatus != StockStatus.outOfStock && quantity > 0;
  bool get needsPriceRefresh =>
      lastPriceUpdate == null || DateTime.now().difference(lastPriceUpdate!).inDays >= 30;

  SellerProduct copyWith({
    double? price,
    StockStatus? stockStatus,
    int? quantity,
    double? offerPrice,
    bool clearOffer = false,
    DateTime? offerStart,
    DateTime? offerExpiry,
  }) => SellerProduct(
        id: id,
        catalogId: catalogId,
        name: name,
        icon: icon,
        price: price ?? this.price,
        stockStatus: stockStatus ?? this.stockStatus,
        quantity: quantity ?? this.quantity,
        offerPrice: clearOffer ? null : offerPrice ?? this.offerPrice,
        offerStart: clearOffer ? null : offerStart ?? this.offerStart,
        offerExpiry: clearOffer ? null : offerExpiry ?? this.offerExpiry,
        lastPriceUpdate: DateTime.now(),
      );
}

@immutable
class ProductRequest {
  const ProductRequest({
    required this.id,
    required this.productName,
    required this.category,
    required this.interestedBuyers,
    required this.radiusKm,
    required this.expiresAt,
    this.icon = '🛒',
    this.targetPrice,
    this.imagePath,
    this.isSellerSubmitted = false,
  });

  final String id;
  final String productName;
  final String category;
  final int interestedBuyers;
  final double radiusKm;
  final DateTime expiresAt;
  final String icon;
  final double? targetPrice;
  final String? imagePath;
  final bool isSellerSubmitted;
}

@immutable
class SellerResponse {
  const SellerResponse({
    required this.requestId,
    required this.isAvailable,
    this.price,
    this.stock,
    this.offerPrice,
  });

  final String requestId;
  final bool isAvailable;
  final double? price;
  final int? stock;
  final double? offerPrice;
}

@immutable
class SellerInsight {
  const SellerInsight({required this.title, required this.productName, required this.score, required this.type});
  final String title;
  final String productName;
  final int score;
  final String type;
}

@immutable
class SellerState {
  const SellerState({
    this.mobile = '',
    this.isOtpSent = false,
    this.isAuthenticated = false,
    this.seller,
    this.products = const [],
    this.requests = const [],
    this.responses = const [],
    this.insights = const [],
  });

  final String mobile;
  final bool isOtpSent;
  final bool isAuthenticated;
  final Seller? seller;
  final List<SellerProduct> products;
  final List<ProductRequest> requests;
  final List<SellerResponse> responses;
  final List<SellerInsight> insights;

  SellerState copyWith({
    String? mobile,
    bool? isOtpSent,
    bool? isAuthenticated,
    Seller? seller,
    List<SellerProduct>? products,
    List<ProductRequest>? requests,
    List<SellerResponse>? responses,
    List<SellerInsight>? insights,
  }) => SellerState(
        mobile: mobile ?? this.mobile,
        isOtpSent: isOtpSent ?? this.isOtpSent,
        isAuthenticated: isAuthenticated ?? this.isAuthenticated,
        seller: seller ?? this.seller,
        products: products ?? this.products,
        requests: requests ?? this.requests,
        responses: responses ?? this.responses,
        insights: insights ?? this.insights,
      );
}
