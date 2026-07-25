import 'package:flutter/foundation.dart';

@immutable
class Brand {
  const Brand({required this.id, required this.name, required this.verified});

  final String id;
  final String name;
  final bool verified;

  factory Brand.fromJson(Map<String, dynamic> json) => Brand(
        id: json['id'] as String,
        name: json['name'] as String,
        verified: json['verified'] as bool? ?? false,
      );
}
