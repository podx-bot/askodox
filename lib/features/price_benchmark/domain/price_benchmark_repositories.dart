import 'price_benchmark_models.dart';

abstract interface class OnlinePriceRepository { Future<List<OnlinePriceSource>> sources(); Future<List<OnlinePriceListing>> listingsFor(String productId); }
abstract interface class PriceBenchmarkRepository { Future<PriceBenchmark?> benchmarkFor(String productId); }
abstract interface class PriceHistoryRepository { Future<List<PriceHistoryPoint>> historyFor(String productId,{required int days}); }

