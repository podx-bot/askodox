import '../domain/communication_models.dart';
import '../domain/communication_repository.dart';

class MockCommunicationRepository implements CommunicationRepository {
  final now = DateTime.now();
  @override Future<List<AppNotification>> notifications() async => [
    AppNotification(id: 'n1', audience: Audience.buyer, category: NotificationCategory.price, title: 'Price drop', message: MessageTemplates.priceDrop('Organic rice 5 kg'), createdAt: now.subtract(const Duration(minutes: 18))),
    AppNotification(id: 'n2', audience: Audience.buyer, category: NotificationCategory.availability, title: 'Back in stock', message: MessageTemplates.productAvailable('Fresh mangoes'), createdAt: now.subtract(const Duration(hours: 2))),
    AppNotification(id: 'n3', audience: Audience.seller, category: NotificationCategory.request, title: 'New buyer request', message: 'A buyer nearby wants 3 packs of ground coffee.', createdAt: now.subtract(const Duration(hours: 4))),
    AppNotification(id: 'n4', audience: Audience.seller, category: NotificationCategory.subscription, title: 'Subscription reminder', message: MessageTemplates.subscriptionReminder('30 July'), createdAt: now.subtract(const Duration(days: 1)), isRead: true),
  ];
  @override Future<List<BuyerRequest>> requests() async => [BuyerRequest(id: 'r1', product: 'Ground coffee 500 g', quantity: 3, preferredPrice: 320, radiusKm: 8, notes: 'Medium roast preferred', createdAt: now.subtract(const Duration(hours: 4)))];
  @override Future<List<ShopFollow>> followedShops() async => [ShopFollow('shop-2', 'Green Basket', now.subtract(const Duration(days: 3)))];
  @override Future<List<Campaign>> campaigns() async => [Campaign(id: 'c1', name: 'Weekend essentials', type: CampaignType.weekend, value: 10, status: CampaignStatus.running, startsAt: now, endsAt: now.add(const Duration(days: 2)))];
  @override Future<List<Announcement>> announcements() async => [];
  @override Future<EngagementMetrics> metrics() async => const EngagementMetrics(shopViews: 428, productViews: 1260, offerClicks: 184, followActions: 62, buyerRequests: 31, watchlistAdditions: 97);
  @override Future<NotificationPreferences> preferences() async => const NotificationPreferences();
}
