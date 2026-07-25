enum AdminRole { superAdmin, catalogAdmin, sellerVerificationAdmin, moderationAdmin, supportAdmin }

extension AdminRoleX on AdminRole {
  String get label => switch (this) {
        AdminRole.superAdmin => 'Super Admin',
        AdminRole.catalogAdmin => 'Catalog Admin',
        AdminRole.sellerVerificationAdmin => 'Seller Verification Admin',
        AdminRole.moderationAdmin => 'Moderation Admin',
        AdminRole.supportAdmin => 'Support Admin',
      };
}

class AdminUser {
  const AdminUser({required this.id, required this.name, required this.role});
  final String id;
  final String name;
  final AdminRole role;
}

enum SellerVerificationStatus { pending, approved, rejected, moreInformation, suspended }

class SellerVerificationCase {
  const SellerVerificationCase({required this.id, required this.ownerName, required this.shopName, required this.mobile, required this.category, required this.address, required this.coordinates, required this.shopPhotoRef, required this.businessDocumentRef, required this.registeredAt, required this.status, this.internalNotes = const []});
  final String id, ownerName, shopName, mobile, category, address, coordinates;
  final String shopPhotoRef, businessDocumentRef;
  final DateTime registeredAt;
  final SellerVerificationStatus status;
  final List<String> internalNotes;
  SellerVerificationCase copyWith({SellerVerificationStatus? status, List<String>? internalNotes}) => SellerVerificationCase(id: id, ownerName: ownerName, shopName: shopName, mobile: mobile, category: category, address: address, coordinates: coordinates, shopPhotoRef: shopPhotoRef, businessDocumentRef: businessDocumentRef, registeredAt: registeredAt, status: status ?? this.status, internalNotes: internalNotes ?? this.internalNotes);
}

enum CatalogProductStatus { active, archived }
class AdminCatalogProduct {
  const AdminCatalogProduct({required this.id, required this.name, required this.brand, required this.category, required this.subcategory, required this.variant, required this.packSize, required this.barcodeRef, required this.imageRef, required this.searchKeywords, this.status = CatalogProductStatus.active});
  final String id, name, brand, category, subcategory, variant, packSize, barcodeRef, imageRef;
  final List<String> searchKeywords;
  final CatalogProductStatus status;
  AdminCatalogProduct copyWith({String? name, CatalogProductStatus? status}) => AdminCatalogProduct(id: id, name: name ?? this.name, brand: brand, category: category, subcategory: subcategory, variant: variant, packSize: packSize, barcodeRef: barcodeRef, imageRef: imageRef, searchKeywords: searchKeywords, status: status ?? this.status);
}

enum ProductRequestStatus { pending, addedToCatalog, linked, rejected, needsDetails, duplicate, closed }
class ProductVerificationRequest {
  const ProductVerificationRequest({required this.id, required this.name, required this.imageRef, required this.category, required this.buyerRequests, required this.sellerRequests, required this.location, required this.requestedAt, required this.similarMatches, required this.demandScore, this.status = ProductRequestStatus.pending, this.linkedProductId});
  final String id, name, imageRef, category, location;
  final int buyerRequests, sellerRequests, demandScore;
  final DateTime requestedAt;
  final List<String> similarMatches;
  final ProductRequestStatus status;
  final String? linkedProductId;
  ProductVerificationRequest copyWith({ProductRequestStatus? status, String? linkedProductId}) => ProductVerificationRequest(id: id, name: name, imageRef: imageRef, category: category, buyerRequests: buyerRequests, sellerRequests: sellerRequests, location: location, requestedAt: requestedAt, similarMatches: similarMatches, demandScore: demandScore, status: status ?? this.status, linkedProductId: linkedProductId ?? this.linkedProductId);
}

enum ModerationCaseType { wrongPrice, misleadingOffer, incorrectStock, duplicateListing, prohibitedListing, suspiciousPrice }
enum ModerationAction { dismiss, warnSeller, correctListing, disableListing, suspendSeller, escalate }
enum ModerationStatus { open, investigating, resolved, escalated }
class ModerationCase {
  const ModerationCase({required this.id, required this.product, required this.seller, required this.type, required this.reportedPrice, required this.currentPrice, required this.reporterNote, required this.reportedAt, required this.evidenceRef, this.status = ModerationStatus.open, this.listingDisabled = false, this.internalNotes = const []});
  final String id, product, seller, reporterNote, evidenceRef;
  final ModerationCaseType type;
  final double reportedPrice, currentPrice;
  final DateTime reportedAt;
  final ModerationStatus status;
  final bool listingDisabled;
  final List<String> internalNotes;
  ModerationCase copyWith({ModerationStatus? status, bool? listingDisabled, List<String>? internalNotes}) => ModerationCase(id: id, product: product, seller: seller, type: type, reportedPrice: reportedPrice, currentPrice: currentPrice, reporterNote: reporterNote, reportedAt: reportedAt, evidenceRef: evidenceRef, status: status ?? this.status, listingDisabled: listingDisabled ?? this.listingDisabled, internalNotes: internalNotes ?? this.internalNotes);
}

class AuditLogEntry {
  const AuditLogEntry({required this.id, required this.adminRole, required this.action, required this.entityType, required this.entity, required this.timestamp, required this.reason, required this.previousStatus, required this.newStatus});
  final String id, action, entityType, entity, reason, previousStatus, newStatus;
  final AdminRole adminRole;
  final DateTime timestamp;
}

enum SupportPriority { low, medium, high, urgent }
enum SupportStatus { open, inProgress, waitingForUser, resolved, closed }
class SupportCase {
  const SupportCase({required this.id, required this.subject, required this.type, required this.priority, required this.status, this.assignee, this.replies = const []});
  final String id, subject, type;
  final SupportPriority priority;
  final SupportStatus status;
  final String? assignee;
  final List<String> replies;
  SupportCase copyWith({SupportPriority? priority, SupportStatus? status, String? assignee, List<String>? replies}) => SupportCase(id: id, subject: subject, type: type, priority: priority ?? this.priority, status: status ?? this.status, assignee: assignee ?? this.assignee, replies: replies ?? this.replies);
}

class AdminDashboardMetrics {
  const AdminDashboardMetrics(this.values);
  final Map<String, int> values;
}
