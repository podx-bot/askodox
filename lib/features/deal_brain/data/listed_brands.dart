import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_models.dart';
import '../../../core/providers/backend_providers.dart';

/// Brand names that real ASKODOX listings carry (`GET /api/products/brands`)
/// -- the learned vocabulary used to recognise a brand in any category.
/// Empty when offline; phrasing and short replies still work without it.
final askodoxListedBrandsProvider = FutureProvider<Set<String>>((ref) async {
  try {
    final result = await ref.read(apiClientProvider).get<Map<String, Object?>>('/api/products/brands');
    if (result is! ApiSuccess<Map<String, Object?>>) return const {};
    return {
      for (final brand in (result.data['brands'] as List? ?? const []))
        if ('$brand'.trim().length >= 2) '$brand'.trim(),
    };
  } catch (_) {
    return const {};
  }
});
