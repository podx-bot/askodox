import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_price_benchmark_repository.dart';
import '../domain/price_benchmark_models.dart';
import '../domain/price_benchmark_repositories.dart';

final priceBenchmarkRepositoryProvider=Provider<MockPriceBenchmarkRepository>((ref)=>MockPriceBenchmarkRepository());
final onlinePriceRepositoryProvider=Provider<OnlinePriceRepository>((ref)=>ref.watch(priceBenchmarkRepositoryProvider));
final priceHistoryRepositoryProvider=Provider<PriceHistoryRepository>((ref)=>ref.watch(priceBenchmarkRepositoryProvider));
final onlinePriceListingsProvider=FutureProvider.family<List<OnlinePriceListing>,String>((ref,id)=>ref.watch(onlinePriceRepositoryProvider).listingsFor(id));
final priceBenchmarkProvider=FutureProvider.family<PriceBenchmark?,String>((ref,id)=>ref.watch(priceBenchmarkRepositoryProvider).benchmarkFor(id));
final priceHistoryRangeProvider=StateProvider<int>((ref)=>7);
final priceHistoryProvider=FutureProvider.family<List<PriceHistoryPoint>,String>((ref,id)=>ref.watch(priceHistoryRepositoryProvider).historyFor(id,days:ref.watch(priceHistoryRangeProvider)));

