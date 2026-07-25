import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/product.dart';
import '../data/demo_home_repository.dart';
import '../domain/home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository>((ref) => DemoHomeRepository());

final featuredProductsProvider = FutureProvider<List<Product>>(
  (ref) => ref.watch(homeRepositoryProvider).featuredProducts(),
);
