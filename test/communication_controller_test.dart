import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/communication/application/communication_controller.dart';
import 'package:podx/features/communication/data/mock_communication_repository.dart';
import 'package:podx/features/communication/domain/communication_models.dart';

void main() {
  test('buyer request and seller response create audience notifications', () async {
    final controller = CommunicationController(MockCommunicationRepository());
    await Future<void>.delayed(Duration.zero);

    controller.createRequest(product: 'Millet flour', quantity: 2, price: 150, radius: 4, notes: 'Organic');
    final request = controller.state.requests.first;
    expect(controller.state.notifications.first.audience, Audience.seller);
    expect(request.status, BuyerRequestStatus.pending);

    controller.respond(request.id, price: 145, quantity: 2, date: DateTime(2026, 7, 26));
    expect(controller.state.requests.first.status, BuyerRequestStatus.sellerResponded);
    expect(controller.state.notifications.first.audience, Audience.buyer);
  });

  test('campaign launch notifies local followers', () async {
    final controller = CommunicationController(MockCommunicationRepository());
    await Future<void>.delayed(Duration.zero);
    final before = controller.state.notifications.length;
    controller.createCampaign(name: 'Festival savings', type: CampaignType.festival, value: 15, start: DateTime.now(), end: DateTime.now().add(const Duration(days: 5)));
    expect(controller.state.campaigns.first.status, CampaignStatus.running);
    expect(controller.state.notifications.length, greaterThan(before));
    expect(controller.state.notifications.first.category, NotificationCategory.offer);
  });

  test('notification lifecycle supports read archive and delete', () async {
    final controller = CommunicationController(MockCommunicationRepository());
    await Future<void>.delayed(Duration.zero);
    final id = controller.state.notifications.first.id;
    controller.markRead(id);
    expect(controller.state.notifications.firstWhere((n) => n.id == id).isRead, isTrue);
    controller.archive(id);
    expect(controller.state.notifications.firstWhere((n) => n.id == id).isArchived, isTrue);
    controller.delete(id);
    expect(controller.state.notifications.any((n) => n.id == id), isFalse);
  });
}
