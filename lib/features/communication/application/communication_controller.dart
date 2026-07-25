import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/mock_communication_repository.dart';
import '../domain/communication_models.dart';
import '../domain/communication_repository.dart';

class CommunicationState {
  const CommunicationState({this.loading = true, this.notifications = const [], this.requests = const [], this.followedShops = const [], this.campaigns = const [], this.announcements = const [], this.metrics = const EngagementMetrics(), this.preferences = const NotificationPreferences()});
  final bool loading;
  final List<AppNotification> notifications;
  final List<BuyerRequest> requests;
  final List<ShopFollow> followedShops;
  final List<Campaign> campaigns;
  final List<Announcement> announcements;
  final EngagementMetrics metrics;
  final NotificationPreferences preferences;
  CommunicationState copyWith({bool? loading, List<AppNotification>? notifications, List<BuyerRequest>? requests, List<ShopFollow>? followedShops, List<Campaign>? campaigns, List<Announcement>? announcements, EngagementMetrics? metrics, NotificationPreferences? preferences}) => CommunicationState(loading: loading ?? this.loading, notifications: notifications ?? this.notifications, requests: requests ?? this.requests, followedShops: followedShops ?? this.followedShops, campaigns: campaigns ?? this.campaigns, announcements: announcements ?? this.announcements, metrics: metrics ?? this.metrics, preferences: preferences ?? this.preferences);
}

final communicationRepositoryProvider = Provider<CommunicationRepository>((_) => MockCommunicationRepository());
final communicationControllerProvider = StateNotifierProvider<CommunicationController, CommunicationState>((ref) => CommunicationController(ref.read(communicationRepositoryProvider)));

class CommunicationController extends StateNotifier<CommunicationState> {
  CommunicationController(this.repository) : super(const CommunicationState()) { _load(); }
  final CommunicationRepository repository;
  Future<void> _load() async { state = CommunicationState(loading: false, notifications: await repository.notifications(), requests: await repository.requests(), followedShops: await repository.followedShops(), campaigns: await repository.campaigns(), announcements: await repository.announcements(), metrics: await repository.metrics(), preferences: await repository.preferences()); }
  void markRead(String id) => state = state.copyWith(notifications: [for (final n in state.notifications) n.id == id ? n.copyWith(isRead: true) : n]);
  void markAllRead() => state = state.copyWith(notifications: [for (final n in state.notifications) n.copyWith(isRead: true)]);
  void archive(String id) => state = state.copyWith(notifications: [for (final n in state.notifications) n.id == id ? n.copyWith(isArchived: true) : n]);
  void delete(String id) => state = state.copyWith(notifications: state.notifications.where((n) => n.id != id).toList());
  void createRequest({required String product, required int quantity, required double price, required double radius, required String notes}) { final request = BuyerRequest(id: 'r${DateTime.now().microsecondsSinceEpoch}', product: product, quantity: quantity, preferredPrice: price, radiusKm: radius, notes: notes, createdAt: DateTime.now()); state = state.copyWith(requests: [request, ...state.requests], notifications: [AppNotification(id: 'n${DateTime.now().microsecondsSinceEpoch}', audience: Audience.seller, category: NotificationCategory.request, title: 'New buyer request', message: '$quantity × $product requested within ${radius.toStringAsFixed(0)} km.', createdAt: DateTime.now()), ...state.notifications]); }
  void respond(String id, {required double price, required int quantity, required DateTime date}) { final request = state.requests.firstWhere((r) => r.id == id); state = state.copyWith(requests: [for (final r in state.requests) if (r.id == id) r.copyWith(status: BuyerRequestStatus.sellerResponded, sellerName: 'PODX Demo Store', offerPrice: price, offerQuantity: quantity, availabilityDate: date) else r], notifications: [AppNotification(id: 'n${DateTime.now().microsecondsSinceEpoch}', audience: Audience.buyer, category: NotificationCategory.request, title: 'Seller response', message: 'PODX Demo Store offered $quantity × ${request.product} at ₹${price.toStringAsFixed(0)}.', createdAt: DateTime.now()), ...state.notifications]); }
  void setRequestStatus(String id, BuyerRequestStatus status) => state = state.copyWith(requests: [for (final r in state.requests) r.id == id ? r.copyWith(status: status) : r]);
  void follow(String id, String name) { if (state.followedShops.any((s) => s.shopId == id)) return; state = state.copyWith(followedShops: [...state.followedShops, ShopFollow(id, name, DateTime.now())]); }
  void unfollow(String id) => state = state.copyWith(followedShops: state.followedShops.where((s) => s.shopId != id).toList());
  void createCampaign({required String name, required CampaignType type, required double value, required DateTime start, required DateTime end}) { final campaign = Campaign(id: 'c${DateTime.now().microsecondsSinceEpoch}', name: name, type: type, value: value, status: start.isAfter(DateTime.now()) ? CampaignStatus.scheduled : CampaignStatus.running, startsAt: start, endsAt: end); state = state.copyWith(campaigns: [campaign, ...state.campaigns], notifications: [for (final shop in state.followedShops) AppNotification(id: 'n${shop.shopId}${DateTime.now().microsecondsSinceEpoch}', audience: Audience.buyer, category: NotificationCategory.offer, title: 'Offer started', message: '${shop.shopName}: ${MessageTemplates.offerStarted(name)}', createdAt: DateTime.now()), ...state.notifications]); }
  void updatePreferences(NotificationPreferences value) => state = state.copyWith(preferences: value);
  void publishAnnouncement(String title, String body, AnnouncementType type) { final item = Announcement('a${DateTime.now().microsecondsSinceEpoch}', title, body, type, DateTime.now()); final audience = type == AnnouncementType.seller ? Audience.seller : Audience.buyer; state = state.copyWith(announcements: [item, ...state.announcements], notifications: [AppNotification(id: 'n${DateTime.now().microsecondsSinceEpoch}', audience: audience, category: NotificationCategory.system, title: title, message: body, createdAt: DateTime.now()), ...state.notifications]); }
}
