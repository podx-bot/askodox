import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/communication_controller.dart';
import '../domain/communication_models.dart';

String _words(String value) => value.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)!.toLowerCase()}',
    );

class NotificationCenterScreen extends ConsumerWidget {
  const NotificationCenterScreen({this.audience = Audience.buyer, super.key});
  final Audience audience;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(communicationControllerProvider);
    final items = state.notifications.where((item) => item.audience == audience && !item.isArchived).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Communication center'),
        actions: [
          IconButton(
            tooltip: 'Mark all read',
            onPressed: () => ref.read(communicationControllerProvider.notifier).markAllRead(),
            icon: const Icon(Icons.done_all),
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const _Empty(icon: Icons.notifications_none, text: 'No notifications yet')
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final item = items[index];
                    return Card(
                      child: ListTile(
                        onTap: () => ref.read(communicationControllerProvider.notifier).markRead(item.id),
                        leading: Icon(item.isRead ? Icons.notifications_none : Icons.notifications_active),
                        title: Text(
                          item.title,
                          style: TextStyle(fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold),
                        ),
                        subtitle: Text('${item.message}\n${_words(item.category.name)}'),
                        isThreeLine: true,
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            final controller = ref.read(communicationControllerProvider.notifier);
                            if (value == 'read') controller.markRead(item.id);
                            if (value == 'archive') controller.archive(item.id);
                            if (value == 'delete') controller.delete(item.id);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'read', child: Text('Mark read')),
                            PopupMenuItem(value: 'archive', child: Text('Archive')),
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class BuyerRequestsScreen extends ConsumerWidget {
  const BuyerRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(communicationControllerProvider).requests;
    return Scaffold(
      appBar: AppBar(title: const Text('My product requests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _request(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Request product'),
      ),
      body: requests.isEmpty
          ? const _Empty(icon: Icons.manage_search, text: 'No product requests yet')
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [for (final request in requests) _RequestCard(request: request, buyer: true)],
            ),
    );
  }

  Future<void> _request(BuildContext context, WidgetRef ref) async {
    final product = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController();
    final radius = TextEditingController(text: '5');
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Request unavailable product'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: product, decoration: const InputDecoration(labelText: 'Product name *')),
              TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity *')),
              TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Preferred price (₹)')),
              TextField(controller: radius, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Preferred radius (km)')),
              TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Additional notes')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send request')),
        ],
      ),
    );
    if (ok == true && product.text.trim().isNotEmpty) {
      ref.read(communicationControllerProvider.notifier).createRequest(
            product: product.text.trim(),
            quantity: int.tryParse(quantity.text) ?? 1,
            price: double.tryParse(price.text) ?? 0,
            radius: double.tryParse(radius.text) ?? 5,
            notes: notes.text.trim(),
          );
    }
  }
}

class SellerEngagementScreen extends ConsumerWidget {
  const SellerEngagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(communicationControllerProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Customer engagement'),
          bottom: const TabBar(tabs: [Tab(text: 'Requests'), Tab(text: 'Followers'), Tab(text: 'Analytics')]),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [for (final request in state.requests) _RequestCard(request: request, buyer: false)],
            ),
            _Followers(state: state),
            _Analytics(metrics: state.metrics),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request, required this.buyer});
  final BuyerRequest request;
  final bool buyer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(request.product, style: Theme.of(context).textTheme.titleMedium)),
                Chip(label: Text(_words(request.status.name))),
              ],
            ),
            Text('${request.quantity} wanted • up to ₹${request.preferredPrice.toStringAsFixed(0)} • ${request.radiusKm.toStringAsFixed(0)} km'),
            if (request.notes.isNotEmpty) Text(request.notes),
            if (request.sellerName != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${request.sellerName}: ${request.offerQuantity} for ₹${request.offerPrice?.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            const SizedBox(height: 8),
            if (!buyer && request.status == BuyerRequestStatus.pending)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: () => _respond(context, ref),
                  icon: const Icon(Icons.reply),
                  label: const Text('Respond'),
                ),
              ),
            if (buyer && request.status == BuyerRequestStatus.sellerResponded)
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => ref.read(communicationControllerProvider.notifier).setRequestStatus(request.id, BuyerRequestStatus.closed),
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    onPressed: () => ref.read(communicationControllerProvider.notifier).setRequestStatus(request.id, BuyerRequestStatus.accepted),
                    child: const Text('Accept'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _respond(BuildContext context, WidgetRef ref) async {
    final price = TextEditingController(text: request.preferredPrice.toStringAsFixed(0));
    final quantity = TextEditingController(text: request.quantity.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Respond to ${request.product}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: price, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Offer price (₹)')),
            TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Offer quantity')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send offer')),
        ],
      ),
    );
    if (ok == true) {
      ref.read(communicationControllerProvider.notifier).respond(
            request.id,
            price: double.tryParse(price.text) ?? 0,
            quantity: int.tryParse(quantity.text) ?? 1,
            date: DateTime.now().add(const Duration(days: 1)),
          );
    }
  }
}

class CommunicationPreferencesScreen extends ConsumerWidget {
  const CommunicationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences = ref.watch(communicationControllerProvider).preferences;
    final controller = ref.read(communicationControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('In-app'),
            value: preferences.inApp,
            onChanged: (value) => controller.updatePreferences(preferences.copyWith(inApp: value)),
          ),
          SwitchListTile(
            title: const Text('Push placeholder'),
            value: preferences.push,
            onChanged: (value) => controller.updatePreferences(preferences.copyWith(push: value)),
          ),
          DropdownButtonFormField<NotificationFrequency>(
            initialValue: preferences.frequency,
            decoration: const InputDecoration(labelText: 'Notification frequency'),
            items: NotificationFrequency.values
                .map((item) => DropdownMenuItem(value: item, child: Text(_words(item.name))))
                .toList(),
            onChanged: (value) {
              if (value != null) controller.updatePreferences(preferences.copyWith(frequency: value));
            },
          ),
        ],
      ),
    );
  }
}

class AnnouncementScreen extends ConsumerWidget {
  const AnnouncementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(communicationControllerProvider).announcements;
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _publish(context, ref),
        icon: const Icon(Icons.campaign),
        label: const Text('Publish'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final item in items)
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: Text(item.title),
              subtitle: Text('${item.body}\n${_words(item.type.name)}'),
              isThreeLine: true,
            ),
        ],
      ),
    );
  }

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final body = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Publish announcement'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
            TextField(controller: body, maxLines: 3, decoration: const InputDecoration(labelText: 'Message')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publish')),
        ],
      ),
    );
    if (ok == true && title.text.trim().isNotEmpty) {
      ref.read(communicationControllerProvider.notifier).publishAnnouncement(
            title.text.trim(),
            body.text.trim(),
            AnnouncementType.feature,
          );
    }
  }
}

class CommunicationHubScreen extends StatelessWidget {
  const CommunicationHubScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Communication')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Notification center'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/communications/notifications'),
            ),
            ListTile(
              leading: const Icon(Icons.manage_search),
              title: const Text('Product requests'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/communications/requests'),
            ),
            ListTile(
              leading: const Icon(Icons.storefront),
              title: const Text('Followed shops'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/communications/following'),
            ),
            ListTile(
              leading: const Icon(Icons.tune),
              title: const Text('Notification preferences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/communications/preferences'),
            ),
          ],
        ),
      );
}

class FollowedShopsScreen extends ConsumerWidget {
  const FollowedShopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(communicationControllerProvider).followedShops;
    return Scaffold(
      appBar: AppBar(title: const Text('Followed shops')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final shop in shops)
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.store)),
                title: Text(shop.shopName),
                trailing: OutlinedButton(
                  onPressed: () => ref.read(communicationControllerProvider.notifier).unfollow(shop.shopId),
                  child: const Text('Unfollow'),
                ),
              ),
            ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.store)),
              title: const Text('PODX Demo Store'),
              subtitle: const Text('Recommended nearby'),
              trailing: FilledButton.tonal(
                onPressed: () => ref.read(communicationControllerProvider.notifier).follow('shop-demo', 'PODX Demo Store'),
                child: const Text('Follow'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Followers extends ConsumerWidget {
  const _Followers({required this.state});
  final CommunicationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Followers preview: ${state.followedShops.length}', style: Theme.of(context).textTheme.titleMedium),
          for (final shop in state.followedShops)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.store)),
              title: Text(shop.shopName),
              trailing: TextButton(
                onPressed: () => ref.read(communicationControllerProvider.notifier).unfollow(shop.shopId),
                child: const Text('Unfollow'),
              ),
            ),
        ],
      );
}

class _Analytics extends StatelessWidget {
  const _Analytics({required this.metrics});
  final EngagementMetrics metrics;

  @override
  Widget build(BuildContext context) => GridView.count(
        padding: const EdgeInsets.all(16),
        crossAxisCount: 2,
        childAspectRatio: 1.8,
        children: [
          _Metric(label: 'Shop views', value: '${metrics.shopViews}'),
          _Metric(label: 'Product views', value: '${metrics.productViews}'),
          _Metric(label: 'Buyer requests', value: '${metrics.buyerRequests}'),
          _Metric(label: 'Watchlist additions', value: '${metrics.watchlistAdditions}'),
        ],
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              const Spacer(),
              Text(value, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 12),
            Text(text),
          ],
        ),
      );
}
