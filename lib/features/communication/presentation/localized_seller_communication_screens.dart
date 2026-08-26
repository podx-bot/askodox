import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/communication_controller.dart';
import '../domain/communication_models.dart';

bool _te(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'te';

String _category(NotificationCategory value, bool te) => switch (value) {
      NotificationCategory.price => te ? 'ధర' : 'Price',
      NotificationCategory.availability => te ? 'లభ్యత' : 'Availability',
      NotificationCategory.offer => te ? 'ఆఫర్' : 'Offer',
      NotificationCategory.request => te ? 'అభ్యర్థన' : 'Request',
      NotificationCategory.shop => te ? 'దుకాణం' : 'Shop',
      NotificationCategory.system => te ? 'సిస్టమ్' : 'System',
      NotificationCategory.subscription =>
        te ? 'సబ్‌స్క్రిప్షన్' : 'Subscription',
      NotificationCategory.moderation => te ? 'మోడరేషన్' : 'Moderation',
    };

class LocalizedSellerNotificationCenterScreen extends ConsumerStatefulWidget {
  const LocalizedSellerNotificationCenterScreen({super.key});

  @override
  ConsumerState<LocalizedSellerNotificationCenterScreen> createState() =>
      _LocalizedSellerNotificationCenterScreenState();
}

class _LocalizedSellerNotificationCenterScreenState
    extends ConsumerState<LocalizedSellerNotificationCenterScreen> {
  String search = '';
  NotificationCategory? category;
  bool archived = false;

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    final state = ref.watch(communicationControllerProvider);
    final items = state.notifications.where((n) {
      final text = '${n.title} ${n.message}'.toLowerCase();
      return n.audience == Audience.seller &&
          n.isArchived == archived &&
          (category == null || n.category == category) &&
          text.contains(search.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'విక్రేత నోటిఫికేషన్లు' : 'Seller notifications'),
        actions: [
          IconButton(
            tooltip: te ? 'అన్నీ చదివినట్లు గుర్తించండి' : 'Mark all read',
            onPressed: () => ref
                .read(communicationControllerProvider.notifier)
                .markAllRead(),
            icon: const Icon(Icons.done_all),
          ),
          IconButton(
            tooltip: archived
                ? (te ? 'ఇన్‌బాక్స్' : 'Inbox')
                : (te ? 'ఆర్కైవ్' : 'Archive'),
            onPressed: () => setState(() => archived = !archived),
            icon: Icon(
              archived ? Icons.inbox_outlined : Icons.archive_outlined,
            ),
          ),
        ],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: TextField(
                    onChanged: (value) => setState(() => search = value),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: te
                          ? 'నోటిఫికేషన్లలో వెతకండి'
                          : 'Search notifications',
                      border: const OutlineInputBorder(),
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
                          label: Text(te ? 'అన్నీ' : 'All'),
                          selected: category == null,
                          onSelected: (_) => setState(() => category = null),
                        ),
                      ),
                      for (final value in NotificationCategory.values)
                        Padding(
                          padding: const EdgeInsets.all(4),
                          child: FilterChip(
                            label: Text(_category(value, te)),
                            selected: category == value,
                            onSelected: (_) => setState(() => category = value),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(
                          child: Text(te
                              ? 'ఈ ఫిల్టర్‌కు నోటిఫికేషన్లు లేవు'
                              : 'No notifications match this filter'),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final n = items[index];
                            return Card(
                              child: ListTile(
                                onTap: () => ref
                                    .read(communicationControllerProvider
                                        .notifier)
                                    .markRead(n.id),
                                leading: const CircleAvatar(
                                  child: Icon(Icons.notifications_outlined),
                                ),
                                title: Text(
                                  n.title,
                                  style: TextStyle(
                                    fontWeight: n.isRead
                                        ? FontWeight.normal
                                        : FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '${n.message}\n${_category(n.category, te)}',
                                ),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    final controller = ref.read(
                                      communicationControllerProvider.notifier,
                                    );
                                    if (value == 'read') {
                                      controller.markRead(n.id);
                                    } else if (value == 'archive') {
                                      controller.archive(n.id);
                                    } else if (value == 'delete') {
                                      controller.delete(n.id);
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (!n.isRead)
                                      PopupMenuItem(
                                        value: 'read',
                                        child: Text(te
                                            ? 'చదివినట్లు గుర్తించండి'
                                            : 'Mark read'),
                                      ),
                                    PopupMenuItem(
                                      value: 'archive',
                                      child: Text(te ? 'ఆర్కైవ్' : 'Archive'),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(te ? 'తొలగించు' : 'Delete'),
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
    );
  }
}

class LocalizedSellerEngagementScreen extends ConsumerWidget {
  const LocalizedSellerEngagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = _te(context);
    final state = ref.watch(communicationControllerProvider);
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(te ? 'కస్టమర్ ఎంగేజ్‌మెంట్' : 'Customer engagement'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: te ? 'సమీప అభ్యర్థనలు' : 'Nearby requests'),
              Tab(text: te ? 'ప్రచారాలు' : 'Campaigns'),
              Tab(text: te ? 'అనుచరులు' : 'Followers'),
              Tab(text: te ? 'విశ్లేషణలు' : 'Analytics'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (state.requests.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Text(te
                          ? 'సమీప అభ్యర్థనలు లేవు'
                          : 'No nearby requests'),
                    ),
                  ),
                for (final request in state.requests)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.manage_search),
                      ),
                      title: Text(request.product),
                      subtitle: Text(te
                          ? '${request.quantity} కావాలి • ₹${request.preferredPrice.toStringAsFixed(0)} వరకు • ${request.radiusKm.toStringAsFixed(0)} కి.మీ'
                          : '${request.quantity} wanted • up to ₹${request.preferredPrice.toStringAsFixed(0)} • ${request.radiusKm.toStringAsFixed(0)} km'),
                    ),
                  ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(te ? 'డెమో ప్రచారాలు మాత్రమే' : 'Demo campaigns only'),
                    subtitle: Text(te
                        ? 'ప్రస్తుతానికి బాహ్య మెసేజ్ లేదా చెల్లింపు సేవలు కనెక్ట్ కాలేదు.'
                        : 'External messaging and payment services are not connected in this demo.'),
                  ),
                ),
                for (final campaign in state.campaigns)
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.local_offer),
                      ),
                      title: Text(campaign.name),
                      subtitle: Text(campaign.type.name),
                    ),
                  ),
              ],
            ),
            Center(
              child: Text(
                '${te ? 'అనుచరులు' : 'Followers'}: ${state.followers.length}',
              ),
            ),
            Center(child: Text(te ? 'విశ్లేషణలు' : 'Analytics')),
          ],
        ),
      ),
    );
  }
}
