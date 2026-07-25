enum Audience { buyer, seller }
enum NotificationCategory { price, availability, offer, request, shop, system, subscription, moderation }
enum BuyerRequestStatus { pending, matched, sellerResponded, buyerViewed, accepted, expired, closed }
enum CampaignType { percentageDiscount, flatDiscount, buyXGetY, festival, weekend }
enum CampaignStatus { draft, scheduled, running, paused, expired, completed }
enum NotificationFrequency { instant, dailyDigest, weeklyDigest }
enum AnnouncementType { maintenance, feature, policy, seller, buyer }

class AppNotification {
  const AppNotification({required this.id, required this.audience, required this.category, required this.title, required this.message, required this.createdAt, this.isRead = false, this.isArchived = false});
  final String id, title, message;
  final Audience audience;
  final NotificationCategory category;
  final DateTime createdAt;
  final bool isRead, isArchived;
  AppNotification copyWith({bool? isRead, bool? isArchived}) => AppNotification(id: id, audience: audience, category: category, title: title, message: message, createdAt: createdAt, isRead: isRead ?? this.isRead, isArchived: isArchived ?? this.isArchived);
}

class BuyerRequest {
  const BuyerRequest({required this.id, required this.product, required this.quantity, required this.preferredPrice, required this.radiusKm, required this.notes, required this.createdAt, this.status = BuyerRequestStatus.pending, this.sellerName, this.offerPrice, this.offerQuantity, this.availabilityDate});
  final String id, product, notes;
  final int quantity;
  final double preferredPrice, radiusKm;
  final DateTime createdAt;
  final BuyerRequestStatus status;
  final String? sellerName;
  final double? offerPrice;
  final int? offerQuantity;
  final DateTime? availabilityDate;
  BuyerRequest copyWith({BuyerRequestStatus? status, String? sellerName, double? offerPrice, int? offerQuantity, DateTime? availabilityDate}) => BuyerRequest(id: id, product: product, quantity: quantity, preferredPrice: preferredPrice, radiusKm: radiusKm, notes: notes, createdAt: createdAt, status: status ?? this.status, sellerName: sellerName ?? this.sellerName, offerPrice: offerPrice ?? this.offerPrice, offerQuantity: offerQuantity ?? this.offerQuantity, availabilityDate: availabilityDate ?? this.availabilityDate);
}

class ShopFollow { const ShopFollow(this.shopId, this.shopName, this.followedAt); final String shopId, shopName; final DateTime followedAt; }
class Campaign { const Campaign({required this.id, required this.name, required this.type, required this.value, required this.status, required this.startsAt, required this.endsAt}); final String id, name; final CampaignType type; final double value; final CampaignStatus status; final DateTime startsAt, endsAt; Campaign copyWith({CampaignStatus? status}) => Campaign(id: id, name: name, type: type, value: value, status: status ?? this.status, startsAt: startsAt, endsAt: endsAt); }
class EngagementMetrics { const EngagementMetrics({this.shopViews = 0, this.productViews = 0, this.offerClicks = 0, this.followActions = 0, this.buyerRequests = 0, this.watchlistAdditions = 0}); final int shopViews, productViews, offerClicks, followActions, buyerRequests, watchlistAdditions; }
class NotificationPreferences { const NotificationPreferences({this.inApp = true, this.push = false, this.email = false, this.sms = false, this.quietStart = 22, this.quietEnd = 7, this.frequency = NotificationFrequency.instant}); final bool inApp, push, email, sms; final int quietStart, quietEnd; final NotificationFrequency frequency; NotificationPreferences copyWith({bool? inApp, bool? push, bool? email, bool? sms, int? quietStart, int? quietEnd, NotificationFrequency? frequency}) => NotificationPreferences(inApp: inApp ?? this.inApp, push: push ?? this.push, email: email ?? this.email, sms: sms ?? this.sms, quietStart: quietStart ?? this.quietStart, quietEnd: quietEnd ?? this.quietEnd, frequency: frequency ?? this.frequency); }
class Announcement { const Announcement(this.id, this.title, this.body, this.type, this.publishedAt); final String id, title, body; final AnnouncementType type; final DateTime publishedAt; }

abstract final class MessageTemplates {
  static String priceDrop(String product) => 'Price drop: $product is now available for less.';
  static String offerStarted(String campaign) => 'Offer started: $campaign is live now.';
  static String productAvailable(String product) => '$product is available near you.';
  static String verificationApproved(String shop) => '$shop verification has been approved.';
  static String subscriptionReminder(String date) => 'Your subscription renews on $date.';
  static String campaignEnding(String campaign) => '$campaign is ending soon.';
}
