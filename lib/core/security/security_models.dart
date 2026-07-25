enum Permission { approveSeller, suspendSeller, editCatalog, viewAuditLog, manageSubscriptions, resolveSupportCases, viewAggregatedAnalytics, exportPersonalData, deleteUserData }
enum SecurityRole { guest, buyer, seller, admin, superAdmin, supportAdmin, catalogAdmin, moderationAdmin, sellerVerificationAdmin }
class RolePermission { const RolePermission(this.role, this.permissions); final SecurityRole role; final Set<Permission> permissions; }

enum ConsentType { termsOfService, privacyPolicy, locationAccess, analytics, productRecommendations, marketingNotifications, sellerPromotionalNotifications, communicationPreferences, ageConfirmation }
enum ConsentStatus { accepted, rejected, withdrawn }
class ConsentRecord { const ConsentRecord({required this.type, required this.version, required this.status, required this.timestamp, required this.sourceScreen, required this.required, this.withdrawalTimestamp}); final ConsentType type; final String version; final ConsentStatus status; final DateTime timestamp; final String sourceScreen; final bool required; final DateTime? withdrawalTimestamp; }

enum LegalDocumentType { termsOfService, privacyPolicy, sellerTerms, communityGuidelines, refundAndCancellation, subscriptionTerms, productListingPolicy, prohibitedItemsPolicy, locationAndMapsNotice, analyticsAndCookiesNotice }
class LegalDocumentVersion { const LegalDocumentVersion(this.value, this.publishedAt); final String value; final DateTime publishedAt; }
class LegalDocument { const LegalDocument({required this.type, required this.title, required this.version, required this.body, this.requiresLegalReview=true}); final LegalDocumentType type; final String title; final LegalDocumentVersion version; final String body; final bool requiresLegalReview; }

enum AccountDeletionStatus { notRequested, confirmationRequired, reauthenticationRequired, requested, gracePeriod, cancelled, processing, completed, failed }
class AccountDeletionRequest { const AccountDeletionRequest({required this.userId, required this.status, required this.updatedAt}); final String userId; final AccountDeletionStatus status; final DateTime updatedAt; AccountDeletionRequest withStatus(AccountDeletionStatus value, DateTime now)=>AccountDeletionRequest(userId:userId,status:value,updatedAt:now); }

enum RateLimitState { allowed, warning, temporarilyLimited, blocked, manualReviewRequired }
class RateLimitRule { const RateLimitRule({required this.key, required this.warningAt, required this.limit, required this.blockAt}); final String key; final int warningAt, limit, blockAt; }
enum AbuseReportType { wrongPrice, misleadingOffer, fakeShop, prohibitedProduct, spamSeller, abuse, privacyConcern, appIssue }
class AbuseReport { const AbuseReport({required this.id, required this.type, required this.entityReference, required this.description, required this.createdAt}); final String id; final AbuseReportType type; final String entityReference, description; final DateTime createdAt; }
class BlockedSeller { const BlockedSeller(this.sellerId, this.blockedAt); final String sellerId; final DateTime blockedAt; }

enum FileCategory { productImage, shopPhoto, sellerVerificationDocument, productRequestImage, complaintEvidence, profileImage }
enum MalwareScanStatus { pending, clean, suspicious }
enum UploadStatus { pending, uploaded, failed }
enum ModerationStatus { pending, approved, rejected }
enum FileAccessLevel { public, authenticated, private }
class SecureFileReference { const SecureFileReference({required this.id, required this.category, required this.filename, required this.mimeType, required this.sizeBytes, required this.accessLevel, this.width, this.height, this.expiresAt, this.malwareScanStatus=MalwareScanStatus.pending, this.uploadStatus=UploadStatus.pending, this.moderationStatus=ModerationStatus.pending}); final String id, filename, mimeType; final FileCategory category; final int sizeBytes; final int? width,height; final DateTime? expiresAt; final FileAccessLevel accessLevel; final MalwareScanStatus malwareScanStatus; final UploadStatus uploadStatus; final ModerationStatus moderationStatus; }
class FileValidationResult { const FileValidationResult(this.isValid, [this.errors=const []]); final bool isValid; final List<String> errors; }

enum SecurityEventType { login, logout, sessionExpired, accessDenied, sensitiveAction, accountLocked, consentChanged }
class SecurityEvent { const SecurityEvent({required this.type, required this.timestamp, required this.correlationId, this.actorId}); final SecurityEventType type; final DateTime timestamp; final String correlationId; final String? actorId; }
class MaskedValue { const MaskedValue(this.value); final String value; @override String toString()=>value; }
class DeviceSession { const DeviceSession({required this.id, required this.createdAt, required this.lastActiveAt, this.revoked=false}); final String id; final DateTime createdAt,lastActiveAt; final bool revoked; }
enum BuildMode { development, staging, release }
enum FeatureFlag { developerSettings, mockRoleSwitching, mockPayment, mockOtp, mockSync, performanceMonitor, seedReset, adminDemoShortcuts, securitySimulation }
class ReleaseChecklistItem { const ReleaseChecklistItem(this.label,{this.complete=false, this.productionBlocker=true}); final String label; final bool complete,productionBlocker; }

class AuditRecord { const AuditRecord({required this.id, required this.actor, required this.actorRole, required this.permission, required this.action, required this.entity, required this.previousState, required this.newState, required this.reason, required this.timestamp, required this.environment, required this.correlationId, required this.sessionIdentifier}); final String id,actor,actorRole,action,entity,previousState,newState,reason,environment,correlationId,sessionIdentifier; final Permission permission; final DateTime timestamp; }
