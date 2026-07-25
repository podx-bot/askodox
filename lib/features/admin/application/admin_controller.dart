import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock_admin_repository.dart';
import '../domain/admin_models.dart';
import '../domain/admin_repository.dart';

enum AdminSection { dashboard, sellers, catalog, productRequests, searchQuality, moderation, support, auditLog, settings }

Set<AdminSection> sectionsFor(AdminRole role) => switch (role) {
  AdminRole.superAdmin => AdminSection.values.toSet(),
  AdminRole.catalogAdmin => {AdminSection.dashboard, AdminSection.catalog, AdminSection.productRequests, AdminSection.searchQuality, AdminSection.auditLog, AdminSection.settings},
  AdminRole.sellerVerificationAdmin => {AdminSection.dashboard, AdminSection.sellers, AdminSection.auditLog, AdminSection.settings},
  AdminRole.moderationAdmin => {AdminSection.dashboard, AdminSection.moderation, AdminSection.auditLog, AdminSection.settings},
  AdminRole.supportAdmin => {AdminSection.dashboard, AdminSection.support, AdminSection.auditLog, AdminSection.settings},
};

class AdminState {
  const AdminState({this.user, required this.metrics, required this.sellers, required this.catalog, required this.requests, required this.moderation, required this.support, this.audit = const []});
  final AdminUser? user;
  final AdminDashboardMetrics metrics;
  final List<SellerVerificationCase> sellers;
  final List<AdminCatalogProduct> catalog;
  final List<ProductVerificationRequest> requests;
  final List<ModerationCase> moderation;
  final List<SupportCase> support;
  final List<AuditLogEntry> audit;
  AdminState copyWith({AdminUser? user, List<SellerVerificationCase>? sellers, List<AdminCatalogProduct>? catalog, List<ProductVerificationRequest>? requests, List<ModerationCase>? moderation, List<SupportCase>? support, List<AuditLogEntry>? audit}) => AdminState(user: user ?? this.user, metrics: metrics, sellers: sellers ?? this.sellers, catalog: catalog ?? this.catalog, requests: requests ?? this.requests, moderation: moderation ?? this.moderation, support: support ?? this.support, audit: audit ?? this.audit);
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) => MockAdminRepository());
final adminControllerProvider = StateNotifierProvider<AdminController, AdminState>((ref) => AdminController(ref.read(adminRepositoryProvider)));

class AdminController extends StateNotifier<AdminState> {
  AdminController(this.repository) : super(AdminState(metrics: repository.metrics, sellers: repository.sellers, catalog: repository.catalog, requests: repository.productRequests, moderation: repository.moderationCases, support: repository.supportCases));
  final AdminRepository repository;
  Future<void> login(AdminRole role) async => state = state.copyWith(user: await repository.login(role));

  void updateSeller(String id, SellerVerificationStatus status, {String reason = '', String? note}) {
    if ({SellerVerificationStatus.rejected, SellerVerificationStatus.suspended}.contains(status) && reason.trim().isEmpty) throw ArgumentError('A reason is required');
    final old = state.sellers.firstWhere((e) => e.id == id);
    state = state.copyWith(sellers: [for (final item in state.sellers) if (item.id == id) item.copyWith(status: status, internalNotes: note == null ? item.internalNotes : [...item.internalNotes, note]) else item]);
    _audit('${status.name} seller', 'Seller', old.shopName, reason, old.status.name, status.name);
  }

  void approveRequest(String id) {
    final request = state.requests.firstWhere((e) => e.id == id);
    final product = AdminCatalogProduct(id: 'approved-$id', name: request.name, brand: 'Pending brand', category: request.category, subcategory: 'Unassigned', variant: 'Standard', packSize: 'Unspecified', barcodeRef: 'barcode://pending', imageRef: request.imageRef, searchKeywords: [request.name.toLowerCase()]);
    state = state.copyWith(requests: [for (final e in state.requests) if (e.id == id) e.copyWith(status: ProductRequestStatus.addedToCatalog) else e], catalog: [...state.catalog, product]);
    _audit('Product approved', 'Product request', request.name, 'Demand score ${request.demandScore}', request.status.name, ProductRequestStatus.addedToCatalog.name);
  }

  void linkDuplicate(String id, String productId) {
    if (!state.catalog.any((e) => e.id == productId)) throw ArgumentError('Catalog product does not exist');
    final old = state.requests.firstWhere((e) => e.id == id);
    state = state.copyWith(requests: [for (final e in state.requests) if (e.id == id) e.copyWith(status: ProductRequestStatus.duplicate, linkedProductId: productId) else e]);
    _audit('Duplicate product linked', 'Product request', old.name, productId, old.status.name, ProductRequestStatus.duplicate.name);
  }

  void moderate(String id, ModerationAction action, {String reason = ''}) {
    final old = state.moderation.firstWhere((e) => e.id == id);
    if (action == ModerationAction.suspendSeller && reason.trim().isEmpty) throw ArgumentError('A reason is required');
    final status = action == ModerationAction.escalate ? ModerationStatus.escalated : ModerationStatus.resolved;
    state = state.copyWith(moderation: [for (final e in state.moderation) if (e.id == id) e.copyWith(status: status, listingDisabled: action == ModerationAction.disableListing || e.listingDisabled) else e]);
    _audit(action.name, 'Moderation case', old.id, reason, old.status.name, status.name);
  }

  void updateSupport(String id, {SupportStatus? status, SupportPriority? priority, String? assignee, String? reply}) {
    final old = state.support.firstWhere((e) => e.id == id);
    state = state.copyWith(support: [for (final e in state.support) if (e.id == id) e.copyWith(status: status, priority: priority, assignee: assignee, replies: reply == null ? e.replies : [...e.replies, reply]) else e]);
    if (status != null) _audit('Support status changed', 'Support case', old.id, reply ?? '', old.status.name, status.name);
  }

  void _audit(String action, String type, String entity, String reason, String previous, String next) {
    final role = state.user?.role ?? AdminRole.superAdmin;
    state = state.copyWith(audit: [AuditLogEntry(id: 'audit-${DateTime.now().microsecondsSinceEpoch}', adminRole: role, action: action, entityType: type, entity: entity, timestamp: DateTime.now(), reason: reason, previousStatus: previous, newStatus: next), ...state.audit]);
  }
}
