import '../domain/watchlist_models.dart';
import '../domain/watchlist_repository.dart';
class MockWatchlistRepository implements WatchlistRepository {
  final List<WatchlistItem> _items=[]; final List<ProductAlert> _alerts=[]; AlertPreference _preferences=const AlertPreference();
  @override List<WatchlistItem> get items=>List.unmodifiable(_items); @override List<ProductAlert> get alerts=>List.unmodifiable(_alerts); @override AlertPreference get preferences=>_preferences;
  @override void saveItem(WatchlistItem item){_items.removeWhere((e)=>e.productId==item.productId);_items.add(item);} @override void removeItem(String id)=>_items.removeWhere((e)=>e.productId==id);
  @override void saveAlerts(List<ProductAlert> value){_alerts..clear()..addAll(value);} @override void savePreferences(AlertPreference value)=>_preferences=value;
}
