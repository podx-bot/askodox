import 'admin_models.dart';

abstract interface class AdminRepository {
  Future<AdminUser> login(AdminRole role);
  AdminDashboardMetrics get metrics;
  List<SellerVerificationCase> get sellers;
  List<AdminCatalogProduct> get catalog;
  List<ProductVerificationRequest> get productRequests;
  List<ModerationCase> get moderationCases;
  List<SupportCase> get supportCases;
}
