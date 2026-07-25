import 'communication_models.dart';

abstract interface class CommunicationRepository {
  Future<List<AppNotification>> notifications();
  Future<List<BuyerRequest>> requests();
  Future<List<ShopFollow>> followedShops();
  Future<List<Campaign>> campaigns();
  Future<List<Announcement>> announcements();
  Future<EngagementMetrics> metrics();
  Future<NotificationPreferences> preferences();
}
