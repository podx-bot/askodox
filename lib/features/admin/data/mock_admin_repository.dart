import '../domain/admin_models.dart';
import '../domain/admin_repository.dart';

class MockAdminRepository implements AdminRepository {
  @override Future<AdminUser> login(AdminRole role) async => AdminUser(id: 'admin-1', name: 'PODX Admin', role: role);
  @override AdminDashboardMetrics get metrics => const AdminDashboardMetrics({'Total buyers': 1240, 'Total sellers': 86, 'Verified sellers': 71, 'Pending seller approvals': 9, 'Total catalog products': 3240, 'Pending product requests': 18, 'Active seller listings': 8920, 'Out-of-stock listings': 214, 'Wrong price reports': 12, 'Open moderation cases': 27, 'Active alerts generated': 640, 'High-demand products': 42});
  @override List<SellerVerificationCase> get sellers => [SellerVerificationCase(id: 's1', ownerName: 'Anil Kumar', shopName: 'Anil Kirana', mobile: '••••••3210', category: 'Groceries', address: 'Madhapur, Hyderabad', coordinates: '17.448, 78.391', shopPhotoRef: 'ref://shop/s1', businessDocumentRef: 'ref://document/s1', registeredAt: DateTime(2026, 7, 20), status: SellerVerificationStatus.pending)];
  @override List<AdminCatalogProduct> get catalog => const [AdminCatalogProduct(id: 'p1', name: 'Organic Toor Dal', brand: 'PODX Select', category: 'Groceries', subcategory: 'Pulses', variant: 'Organic', packSize: '1 kg', barcodeRef: 'barcode://pending', imageRef: 'ref://product/p1', searchKeywords: ['dal', 'toor', 'కందిపప్పు'])];
  @override List<ProductVerificationRequest> get productRequests => [ProductVerificationRequest(id: 'r1', name: 'Organic Toor Dal 1 kg', imageRef: 'ref://request/r1', category: 'Groceries', buyerRequests: 18, sellerRequests: 4, location: '5 km around Madhapur', requestedAt: DateTime(2026, 7, 21), similarMatches: const ['Organic Toor Dal'], demandScore: 88)];
  @override List<ModerationCase> get moderationCases => [ModerationCase(id: 'm1', product: 'Sunflower Oil 1 L', seller: 'City Mart', type: ModerationCaseType.wrongPrice, reportedPrice: 120, currentPrice: 190, reporterNote: 'Shelf price differs', reportedAt: DateTime(2026, 7, 22), evidenceRef: 'ref://evidence/m1')];
  @override List<SupportCase> get supportCases => const [SupportCase(id: 'c1', subject: 'Price alert did not arrive', type: 'App issue', priority: SupportPriority.high, status: SupportStatus.open)];
}
