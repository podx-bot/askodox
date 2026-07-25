import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/admin/application/admin_controller.dart';
import 'package:podx/features/admin/data/mock_admin_repository.dart';
import 'package:podx/features/admin/domain/admin_models.dart';

void main() {
  late AdminController controller;
  setUp(() => controller = AdminController(MockAdminRepository()));

  test('seller approval and rejection create audit records', () {
    controller.updateSeller('s1', SellerVerificationStatus.approved);
    expect(controller.state.sellers.single.status, SellerVerificationStatus.approved);
    expect(() => controller.updateSeller('s1', SellerVerificationStatus.rejected), throwsArgumentError);
    controller.updateSeller('s1', SellerVerificationStatus.rejected, reason: 'Invalid registration');
    expect(controller.state.audit, hasLength(2));
  });

  test('product request approval adds catalog product', () {
    final before = controller.state.catalog.length;
    controller.approveRequest('r1');
    expect(controller.state.requests.single.status, ProductRequestStatus.addedToCatalog);
    expect(controller.state.catalog, hasLength(before + 1));
  });

  test('duplicate linking references existing product', () {
    controller.linkDuplicate('r1', 'p1');
    expect(controller.state.requests.single.linkedProductId, 'p1');
    expect(controller.state.requests.single.status, ProductRequestStatus.duplicate);
  });

  test('listing disable and moderation status update are audited', () {
    controller.moderate('m1', ModerationAction.disableListing);
    expect(controller.state.moderation.single.listingDisabled, isTrue);
    expect(controller.state.moderation.single.status, ModerationStatus.resolved);
    expect(controller.state.audit.single.action, ModerationAction.disableListing.name);
  });

  test('seller suspension requires reason', () {
    expect(() => controller.updateSeller('s1', SellerVerificationStatus.suspended), throwsArgumentError);
    controller.updateSeller('s1', SellerVerificationStatus.suspended, reason: 'Repeated violations');
    expect(controller.state.sellers.single.status, SellerVerificationStatus.suspended);
  });

  test('support workflow updates assignment, priority, reply and status', () {
    controller.updateSupport('c1', assignee: 'Support Admin', priority: SupportPriority.urgent, reply: 'Investigating', status: SupportStatus.inProgress);
    final support = controller.state.support.single;
    expect(support.assignee, 'Support Admin');
    expect(support.replies, ['Investigating']);
    expect(support.status, SupportStatus.inProgress);
    expect(controller.state.audit, isNotEmpty);
  });

  test('role based navigation only exposes permitted sections', () {
    expect(sectionsFor(AdminRole.catalogAdmin), containsAll([AdminSection.catalog, AdminSection.productRequests]));
    expect(sectionsFor(AdminRole.catalogAdmin), isNot(contains(AdminSection.sellers)));
    expect(sectionsFor(AdminRole.superAdmin), hasLength(AdminSection.values.length));
  });
}
