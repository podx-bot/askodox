import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/communication_controller.dart';
import '../domain/communication_models.dart';

String _words(String value) => value.replaceAllMapped(
      RegExp(r'([A-Z])'),
      (match) => ' ${match.group(1)!.toLowerCase()}',
    );

class NotificationCenterScreen extends ConsumerStatefulWidget {
  const NotificationCenterScreen({
    this.audience = Audience.buyer,
    super.key,
  });

  final Audience audience;

  @override
  ConsumerState<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState
    extends ConsumerState<NotificationCenterScreen> {
  String search = '';
  NotificationCategory? category;
  bool archived = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(communicationControllerProvider);
    final items = state.notifications.where((notification) {
      final matchesAudience = notification.audience == widget.audience;
      final matchesArchive = notification.isArchived == archived;
      final matchesCategory =
          category == null || notification.category == category;
      final haystack = '${notification.title} ${notification.message}'
          .toLowerCase();
      final matchesSearch = haystack.contains(search.toLowerCase());
      return matchesAudience &&
          matchesArchive &&
          matchesCategory &&
          matchesSearch;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Communication center'),
        actions: [
          IconButton(
            tooltip: 'Mark all read',
            onPressed: () => ref
                .read(communicationControllerProvider.notifier)
                .markAllRead(),
            icon: const Icon(Icons.done_all),
          ),
          IconButton(
            tooltip: archived ? 'Inbox' : 'Archive',
            onPressed: () => setState(() => archived = !archived),
            icon: Icon(
              archived ? Icons.inbox_outlined : Icons.archive_outlined,
            ),
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 900),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: TextField(
                        onChanged: (value) => setState(() => search = value),
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search notifications',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 52,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(4),
                            child: FilterChip(
                              label: const Text('All'),
                              selected: category == null,
                              onSelected: (_) =>
                                  setState(() => category = null),
                            ),
                          ),
                          for (final value in NotificationCategory.values)
                            Padding(
                              padding: const EdgeInsets.all(4),
                              child: FilterChip(
                                label: Text(_words(value.name)),
                                selected: category == value,
                                onSelected: (_) =>
                                    setState(() => category = value),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: items.isEmpty
                          ? const _Empty(
                              icon: Icons.notifications_none,
                              text: 'No notifications match this filter',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: items.length,
                              itemBuilder: (context, index) {
                                final notification = items[index];
                                return Card(
                                  color: notification.isRead
                                      ? null
                                      : Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                          .withValues(alpha: .35),
                                  child: ListTile(
                                    onTap: () => ref
                                        .read(communicationControllerProvider
                                            .notifier)
                                        .markRead(notification.id),
                                    leading: CircleAvatar(
                                      child: Icon(
                                        _categoryIcon(notification.category),
                                      ),
                                    ),
                                    title: Text(
                                      notification.title,
                                      style: TextStyle(
                                        fontWeight: notification.isRead
                                            ? FontWeight.normal
                                            : FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${notification.message}\n'
                                      '${_words(notification.category.name)} • '
                                      '${_relative(notification.createdAt)}',
                                    ),
                                    isThreeLine: true,
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (value) {
                                        final controller = ref.read(
                                          communicationControllerProvider
                                              .notifier,
                                        );
                                        if (value == 'read') {
                                          controller.markRead(notification.id);
                                        } else if (value == 'archive') {
                                          controller.archive(notification.id);
                                        } else if (value == 'delete') {
                                          controller.delete(notification.id);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        if (!notification.isRead)
                                          const PopupMenuItem(
                                            value: 'read',
                                            child: Text('Mark read'),
                                          ),
                                        const PopupMenuItem(
                                          value: 'archive',
                                          child: Text('Archive'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  IconData _categoryIcon(NotificationCategory category) => switch (category) {
        NotificationCategory.price => Icons.trending_down,
        NotificationCategory.availability => Icons.inventory_2_outlined,
        NotificationCategory.offer => Icons.local_offer_outlined,
        NotificationCategory.request => Icons.handshake_outlined,
        NotificationCategory.shop => Icons.store_outlined,
        NotificationCategory.system => Icons.campaign_outlined,
        NotificationCategory.subscription => Icons.workspace_premium_outlined,
        NotificationCategory.moderation => Icons.report_outlined,
      };

  String _relative(DateTime date) {
    final difference = DateTime.now().difference(date);
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return '${difference.inDays}d ago';
  }
}

class BuyerRequestsScreen extends ConsumerWidget {
  const BuyerRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(communicationControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My product requests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _request(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Request product'),
      ),
      body: state.requests.isEmpty
          ? const _Empty(
              icon: Icons.manage_search,
              text: 'No product requests yet',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final request in state.requests)
                  _RequestCard(request: request, buyer: true),
              ],
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
              TextField(
                controller: product,
                decoration: const InputDecoration(labelText: 'Product name *'),
              ),
              TextField(
                controller: quantity,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Quantity *'),
              ),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Preferred price (₹) *'),
              ),
              TextField(
                controller: radius,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Preferred radius (km) *',
                ),
              ),
              TextField(
                controller: notes,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Additional notes'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send request'),
          ),
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
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Customer engagement'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Nearby requests'),
              Tab(text: 'Campaigns'),
              Tab(text: 'Followers'),
              Tab(text: 'Analytics'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final request in state.requests)
                  _RequestCard(request: request, buyer: false),
              ],
            ),
            _Campaigns(state: state),
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
                Expanded(
                  child: Text(
                    request.product,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(_words(request.status.name))),
              ],
            ),
            Text(
              '${request.quantity} wanted • up to '
              '₹${request.preferredPrice.toStringAsFixed(0)} • '
              '${request.radiusKm.toStringAsFixed(0)} km',
            ),
            if (request.notes.isNotEmpty) Text(request.notes),
            if (request.sellerName != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${request.sellerName}: ${request.offerQuantity} for '
                  '₹${request.offerPrice?.toStringAsFixed(0)} • available '
                  '${request.availabilityDate?.toLocal().toString().split(' ').first}',
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
                    onPressed: () => ref
                        .read(communicationControllerProvider.notifier)
                        .setRequestStatus(
                          request.id,
                          BuyerRequestStatus.closed,
                        ),
                    child: const Text('Close'),
                  ),
                  FilledButton(
                    onPressed: () => ref
                        .read(communicationControllerProvider.notifier)
                        .setRequestStatus(
                          request.id,
                          BuyerRequestStatus.accepted,
                        ),
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
    final price = TextEditingController(
      text: request.preferredPrice.toStringAsFixed(0),
    );
    final quantity = TextEditingController(text: request.quantity.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Respond to ${request.product}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: price,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Offer price (₹)'),
            ),
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Offer quantity'),
            ),
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.event),
              title: Text('Availability date'),
              subtitle: Text('Tomorrow (mock)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send offer'),
          ),
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

class _Campaigns extends ConsumerWidget {
  const _Campaigns({required this.state});

  final CommunicationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New campaign'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('Mock campaigns only'),
              subtitle: Text(
                'No messages, email, SMS, push services, or payments are connected.',
              ),
            ),
          ),
          for (final campaign in state.campaigns)
            Card(
              child: ListTile(
                leading:
                    const CircleAvatar(child: Icon(Icons.local_offer)),
                title: Text(campaign.name),
                subtitle: Text(
                  '${_words(campaign.type.name)} • '
                  '${campaign.value.toStringAsFixed(0)} value\n'
                  '${campaign.startsAt.toLocal().toString().split(' ').first} – '
                  '${campaign.endsAt.toLocal().toString().split(' ').first}',
                ),
                isThreeLine: true,
                trailing: Chip(label: Text(_words(campaign.status.name))),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    var type = CampaignType.percentageDiscount;
    final value = TextEditingController(text: '10');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Create mock campaign'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Campaign name'),
              ),
              DropdownButtonFormField<CampaignType>(
                initialValue: type,
                decoration:
                    const InputDecoration(labelText: 'Campaign type'),
                items: [
                  for (final value in CampaignType.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_words(value.name)),
                    ),
                ],
                onChanged: (newValue) {
                  if (newValue != null) setState(() => type = newValue);
                },
              ),
              TextField(
                controller: value,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Discount/value'),
              ),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Schedule'),
                subtitle: Text('Starts now • ends in 7 days'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Save draft'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Launch'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && name.text.isNotEmpty) {
      ref.read(communicationControllerProvider.notifier).createCampaign(
            name: name.text,
            type: type,
            value: double.tryParse(value.text) ?? 0,
            start: DateTime.now(),
            end: DateTime.now().add(const Duration(days: 7)),
          );
    }
  }
}

class _Followers extends ConsumerWidget {
  const _Followers({required this.state});

  final CommunicationState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Followers',
                value: '${state.followedShops.length + 142}',
              ),
            ),
            const Expanded(
              child: _Metric(label: 'New this week', value: '18'),
            ),
          ],
        ),
        const Card(
          child: ListTile(
            leading: Icon(Icons.insights),
            title: Text('Engagement summary'),
            subtitle: Text(
              'Followers engaged with 23% of recent offers. Mock local analytics.',
            ),
          ),
        ),
        const Divider(),
        Text(
          'Followed shops (buyer preview)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final shop in state.followedShops)
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.store)),
            title: Text(shop.shopName),
            subtitle: Text(
              'Followed ${shop.followedAt.toLocal().toString().split(' ').first}',
            ),
            trailing: TextButton(
              onPressed: () => ref
                  .read(communicationControllerProvider.notifier)
                  .unfollow(shop.shopId),
              child: const Text('Unfollow'),
            ),
          ),
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.store)),
          title: const Text('PODX Demo Store'),
          subtitle: const Text('Nearby • groceries'),
          trailing: FilledButton.tonal(
            onPressed: () => ref
                .read(communicationControllerProvider.notifier)
                .follow('shop-demo', 'PODX Demo Store'),
            child: const Text('Follow'),
          ),
        ),
      ],
    );
  }
}

class _Analytics extends StatelessWidget {
  const _Analytics({required this.metrics});

  final EngagementMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final values = {
      'Shop views': metrics.shopViews,
      'Product views': metrics.productViews,
      'Offer clicks': metrics.offerClicks,
      'Follow actions': metrics.followActions,
      'Buyer requests': metrics.buyerRequests,
      'Watchlist additions': metrics.watchlistAdditions,
    };
    return GridView(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 280,
        mainAxisExtent: 130,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      children: [
        for (final entry in values.entries)
          _Metric(label: entry.key, value: '${entry.value}'),
      ],
    );
  }
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

class CommunicationPreferencesScreen extends ConsumerWidget {
  const CommunicationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preferences =
        ref.watch(communicationControllerProvider).preferences;
    final controller = ref.read(communicationControllerProvider.notifier);

    Widget toggle(
      String title,
      String subtitle,
      bool value,
      void Function(bool) onChanged,
    ) =>
        SwitchListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: onChanged,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          toggle(
            'In-app',
            'Notifications inside PODX',
            preferences.inApp,
            (value) => controller.updatePreferences(
              preferences.copyWith(inApp: value),
            ),
          ),
          toggle(
            'Push placeholder',
            'Preference only — no push service connected',
            preferences.push,
            (value) => controller.updatePreferences(
              preferences.copyWith(push: value),
            ),
          ),
          toggle(
            'Email placeholder',
            'Preference only — no emails are sent',
            preferences.email,
            (value) => controller.updatePreferences(
              preferences.copyWith(email: value),
            ),
          ),
          toggle(
            'SMS placeholder',
            'Preference only — no SMS is sent',
            preferences.sms,
            (value) => controller.updatePreferences(
              preferences.copyWith(sms: value),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: const Text('Quiet hours'),
            subtitle: Text(
              '${preferences.quietStart}:00 – ${preferences.quietEnd}:00',
            ),
          ),
          DropdownButtonFormField<NotificationFrequency>(
            initialValue: preferences.frequency,
            decoration:
                const InputDecoration(labelText: 'Notification frequency'),
            items: [
              for (final frequency in NotificationFrequency.values)
                DropdownMenuItem(
                  value: frequency,
                  child: Text(_words(frequency.name)),
                ),
            ],
            onChanged: (value) {
              if (value != null) {
                controller.updatePreferences(
                  preferences.copyWith(frequency: value),
                );
              }
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
    final state = ref.watch(communicationControllerProvider);
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
          const Card(
            child: ListTile(
              title: Text('Audience announcements'),
              subtitle: Text(
                'Publish maintenance, feature, policy, seller, or buyer notices using local mock data.',
              ),
            ),
          ),
          for (final announcement in state.announcements)
            ListTile(
              leading: const Icon(Icons.campaign_outlined),
              title: Text(announcement.title),
              subtitle: Text(
                '${announcement.body}\n${_words(announcement.type.name)}',
              ),
              isThreeLine: true,
            ),
        ],
      ),
    );
  }

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final body = TextEditingController();
    var type = AnnouncementType.maintenance;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Publish announcement'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: body,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
              DropdownButtonFormField<AnnouncementType>(
                initialValue: type,
                items: [
                  for (final value in AnnouncementType.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_words(value.name)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => type = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Publish'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && title.text.isNotEmpty) {
      ref
          .read(communicationControllerProvider.notifier)
          .publishAnnouncement(title.text, body.text, type);
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
              subtitle: const Text('Search, filter, archive, and manage updates'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/communications/notifications'),
            ),
            ListTile(
              leading: const Icon(Icons.manage_search),
              title: const Text('Product requests'),
              subtitle: const Text('Request unavailable products and review offers'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/communications/requests'),
            ),
            ListTile(
              leading: const Icon(Icons.storefront),
              title: const Text('Followed shops'),
              subtitle: const Text('Manage shops and offer updates'),
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
                  onPressed: () => ref
                      .read(communicationControllerProvider.notifier)
                      .unfollow(shop.shopId),
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
                onPressed: () => ref
                    .read(communicationControllerProvider.notifier)
                    .follow('shop-demo', 'PODX Demo Store'),
                child: const Text('Follow'),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
