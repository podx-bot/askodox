import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/communication_controller.dart';
import '../domain/communication_models.dart';

bool _te(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

String _category(NotificationCategory value, bool te) => switch (value) {
      NotificationCategory.price => te ? 'ధర' : 'Price',
      NotificationCategory.availability => te ? 'లభ్యత' : 'Availability',
      NotificationCategory.offer => te ? 'ఆఫర్' : 'Offer',
      NotificationCategory.request => te ? 'అభ్యర్థన' : 'Request',
      NotificationCategory.shop => te ? 'దుకాణం' : 'Shop',
      NotificationCategory.system => te ? 'సిస్టమ్' : 'System',
      NotificationCategory.subscription => te ? 'సబ్‌స్క్రిప్షన్' : 'Subscription',
      NotificationCategory.moderation => te ? 'మోడరేషన్' : 'Moderation',
    };

class LocalizedCommunicationHubScreen extends StatelessWidget {
  const LocalizedCommunicationHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'కమ్యూనికేషన్ కేంద్రం' : 'Communication center')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: Text(te ? 'నోటిఫికేషన్ కేంద్రం' : 'Notification center'),
            subtitle: Text(te ? 'అప్‌డేట్లను వెతకండి, ఫిల్టర్ చేయండి, ఆర్కైవ్ చేయండి' : 'Search, filter, archive, and manage updates'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/communications/notifications'),
          ),
          ListTile(
            leading: const Icon(Icons.manage_search),
            title: Text(te ? 'ఉత్పత్తి అభ్యర్థనలు' : 'Product requests'),
            subtitle: Text(te ? 'దొరకని ఉత్పత్తిని అడిగి, వచ్చిన ఆఫర్లను చూడండి' : 'Request unavailable products and review offers'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/communications/requests'),
          ),
          ListTile(
            leading: const Icon(Icons.storefront),
            title: Text(te ? 'ఫాలో అవుతున్న దుకాణాలు' : 'Followed shops'),
            subtitle: Text(te ? 'దుకాణాలు మరియు ఆఫర్ అప్‌డేట్లను నిర్వహించండి' : 'Manage shops and offer updates'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/communications/following'),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: Text(te ? 'నోటిఫికేషన్ ప్రాధాన్యతలు' : 'Notification preferences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/communications/preferences'),
          ),
        ],
      ),
    );
  }
}

class LocalizedNotificationCenterScreen extends ConsumerStatefulWidget {
  const LocalizedNotificationCenterScreen({super.key});

  @override
  ConsumerState<LocalizedNotificationCenterScreen> createState() => _LocalizedNotificationCenterScreenState();
}

class _LocalizedNotificationCenterScreenState extends ConsumerState<LocalizedNotificationCenterScreen> {
  String search = '';
  NotificationCategory? category;
  bool archived = false;

  @override
  Widget build(BuildContext context) {
    final te = _te(context);
    final state = ref.watch(communicationControllerProvider);
    final items = state.notifications.where((n) {
      final haystack = '${n.title} ${n.message}'.toLowerCase();
      return n.audience == Audience.buyer && n.isArchived == archived &&
          (category == null || n.category == category) && haystack.contains(search.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'నోటిఫికేషన్లు' : 'Notifications'),
        actions: [
          IconButton(
            tooltip: te ? 'అన్నీ చదివినట్లు గుర్తించండి' : 'Mark all read',
            onPressed: () => ref.read(communicationControllerProvider.notifier).markAllRead(),
            icon: const Icon(Icons.done_all),
          ),
          IconButton(
            tooltip: archived ? (te ? 'ఇన్‌బాక్స్' : 'Inbox') : (te ? 'ఆర్కైవ్' : 'Archive'),
            onPressed: () => setState(() => archived = !archived),
            icon: Icon(archived ? Icons.inbox_outlined : Icons.archive_outlined),
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
                    onChanged: (v) => setState(() => search = v),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: te ? 'నోటిఫికేషన్లలో వెతకండి' : 'Search notifications',
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
                      ? Center(child: Text(te ? 'ఈ ఫిల్టర్‌కు నోటిఫికేషన్లు లేవు' : 'No notifications match this filter'))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final n = items[index];
                            final diff = DateTime.now().difference(n.createdAt);
                            final relative = diff.inMinutes < 60
                                ? (te ? '${diff.inMinutes} నిమిషాల క్రితం' : '${diff.inMinutes}m ago')
                                : diff.inHours < 24
                                    ? (te ? '${diff.inHours} గంటల క్రితం' : '${diff.inHours}h ago')
                                    : (te ? '${diff.inDays} రోజుల క్రితం' : '${diff.inDays}d ago');
                            return Card(
                              child: ListTile(
                                onTap: () => ref.read(communicationControllerProvider.notifier).markRead(n.id),
                                leading: const CircleAvatar(child: Icon(Icons.notifications_outlined)),
                                title: Text(n.title, style: TextStyle(fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold)),
                                subtitle: Text('${n.message}\n${_category(n.category, te)} • $relative'),
                                isThreeLine: true,
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) {
                                    final c = ref.read(communicationControllerProvider.notifier);
                                    if (value == 'read') c.markRead(n.id);
                                    if (value == 'archive') c.archive(n.id);
                                    if (value == 'delete') c.delete(n.id);
                                  },
                                  itemBuilder: (_) => [
                                    if (!n.isRead) PopupMenuItem(value: 'read', child: Text(te ? 'చదివినట్లు గుర్తించండి' : 'Mark read')),
                                    PopupMenuItem(value: 'archive', child: Text(te ? 'ఆర్కైవ్' : 'Archive')),
                                    PopupMenuItem(value: 'delete', child: Text(te ? 'తొలగించు' : 'Delete')),
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

class LocalizedBuyerRequestsScreen extends ConsumerWidget {
  const LocalizedBuyerRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = _te(context);
    final state = ref.watch(communicationControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నా ఉత్పత్తి అభ్యర్థనలు' : 'My product requests')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _request(context, ref, te),
        icon: const Icon(Icons.add),
        label: Text(te ? 'ఉత్పత్తిని అడగండి' : 'Request product'),
      ),
      body: state.requests.isEmpty
          ? Center(child: Text(te ? 'ఇంకా ఉత్పత్తి అభ్యర్థనలు లేవు' : 'No product requests yet'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final request in state.requests)
                  Card(
                    child: ListTile(
                      title: Text(request.product),
                      subtitle: Text(te
                          ? '${request.quantity} కావాలి • ₹${request.preferredPrice.toStringAsFixed(0)} వరకు • ${request.radiusKm.toStringAsFixed(0)} కి.మీ'
                          : '${request.quantity} wanted • up to ₹${request.preferredPrice.toStringAsFixed(0)} • ${request.radiusKm.toStringAsFixed(0)} km'),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _request(BuildContext context, WidgetRef ref, bool te) async {
    final product = TextEditingController();
    final quantity = TextEditingController(text: '1');
    final price = TextEditingController();
    final radius = TextEditingController(text: '5');
    final notes = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(te ? 'దొరకని ఉత్పత్తిని అడగండి' : 'Request unavailable product'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: product, decoration: InputDecoration(labelText: te ? 'ఉత్పత్తి పేరు *' : 'Product name *')),
            TextField(controller: quantity, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: te ? 'పరిమాణం *' : 'Quantity *')),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: te ? 'కావాల్సిన ధర (₹) *' : 'Preferred price (₹) *')),
            TextField(controller: radius, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: te ? 'పరిధి (కి.మీ) *' : 'Preferred radius (km) *')),
            TextField(controller: notes, maxLines: 3, decoration: InputDecoration(labelText: te ? 'అదనపు వివరాలు' : 'Additional notes')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(te ? 'రద్దు' : 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(te ? 'అభ్యర్థన పంపండి' : 'Send request')),
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

class LocalizedFollowedShopsScreen extends ConsumerWidget {
  const LocalizedFollowedShopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = _te(context);
    final shops = ref.watch(communicationControllerProvider).followedShops;
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'ఫాలో అవుతున్న దుకాణాలు' : 'Followed shops')),
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
                  child: Text(te ? 'ఫాలో ఆపు' : 'Unfollow'),
                ),
              ),
            ),
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.store)),
              title: const Text('ASKODOX Demo Store'),
              subtitle: Text(te ? 'దగ్గరలో సిఫార్సు చేసినది' : 'Recommended nearby'),
              trailing: FilledButton.tonal(
                onPressed: () => ref.read(communicationControllerProvider.notifier).follow('shop-demo', 'ASKODOX Demo Store'),
                child: Text(te ? 'ఫాలో అవ్వండి' : 'Follow'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class LocalizedCommunicationPreferencesScreen extends ConsumerWidget {
  const LocalizedCommunicationPreferencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = _te(context);
    final preferences = ref.watch(communicationControllerProvider).preferences;
    final controller = ref.read(communicationControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(te ? 'నోటిఫికేషన్ ప్రాధాన్యతలు' : 'Notification preferences')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: Text(te ? 'యాప్‌లో' : 'In-app'),
            subtitle: Text(te ? 'ASKODOX యాప్‌లో నోటిఫికేషన్లు' : 'Notifications inside ASKODOX'),
            value: preferences.inApp,
            onChanged: (v) => controller.updatePreferences(preferences.copyWith(inApp: v)),
          ),
          SwitchListTile(
            title: Text(te ? 'పుష్ నోటిఫికేషన్లు' : 'Push placeholder'),
            subtitle: Text(te ? 'ప్రస్తుతం preference మాత్రమే' : 'Preference only — no push service connected'),
            value: preferences.push,
            onChanged: (v) => controller.updatePreferences(preferences.copyWith(push: v)),
          ),
          SwitchListTile(
            title: Text(te ? 'ఇమెయిల్' : 'Email placeholder'),
            subtitle: Text(te ? 'ప్రస్తుతం ఇమెయిళ్లు పంపబడవు' : 'Preference only — no emails are sent'),
            value: preferences.email,
            onChanged: (v) => controller.updatePreferences(preferences.copyWith(email: v)),
          ),
          SwitchListTile(
            title: Text(te ? 'SMS' : 'SMS placeholder'),
            subtitle: Text(te ? 'ప్రస్తుతం SMS పంపబడదు' : 'Preference only — no SMS is sent'),
            value: preferences.sms,
            onChanged: (v) => controller.updatePreferences(preferences.copyWith(sms: v)),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.bedtime_outlined),
            title: Text(te ? 'నిశ్శబ్ద సమయం' : 'Quiet hours'),
            subtitle: Text('${preferences.quietStart}:00 – ${preferences.quietEnd}:00'),
          ),
        ],
      ),
    );
  }
}
