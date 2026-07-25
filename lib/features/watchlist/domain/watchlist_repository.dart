import 'watchlist_models.dart';
abstract interface class WatchlistRepository {
  List<WatchlistItem> get items; List<ProductAlert> get alerts; AlertPreference get preferences;
  void saveItem(WatchlistItem item); void removeItem(String productId); void saveAlerts(List<ProductAlert> alerts); void savePreferences(AlertPreference value);
}
