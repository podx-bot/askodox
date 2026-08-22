import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../domain/communication_models.dart';

class CommunicationHubScreen extends StatelessWidget {
  const CommunicationHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Communications')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            onTap: () => context.push('/communications/notifications'),
          ),
          ListTile(
            leading: const Icon(Icons.request_page_outlined),
            title: const Text('Requests'),
            onTap: () => context.push('/communications/requests'),
          ),
          ListTile(
            leading: const Icon(Icons.store_outlined),
            title: const Text('Following'),
            onTap: () => context.push('/communications/following'),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Preferences'),
            onTap: () => context.push('/communications/preferences'),
          ),
        ],
      ),
    );
  }
}

class NotificationCenterScreen extends StatelessWidget {
  const NotificationCenterScreen({this.audience = Audience.buyer, super.key});

  final Audience audience;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Center(
        child: Text(
          audience == Audience.seller
              ? 'Seller notifications will appear here.'
              : 'Your notifications will appear here.',
        ),
      ),
    );
  }
}

class BuyerRequestsScreen extends StatelessWidget {
  const BuyerRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Requests will appear here.')),
      );
}

class FollowedShopsScreen extends StatelessWidget {
  const FollowedShopsScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Followed shops will appear here.')),
      );
}

class CommunicationPreferencesScreen extends StatefulWidget {
  const CommunicationPreferencesScreen({super.key});

  @override
  State<CommunicationPreferencesScreen> createState() =>
      _CommunicationPreferencesScreenState();
}

class _CommunicationPreferencesScreenState
    extends State<CommunicationPreferencesScreen> {
  bool inApp = true;
  bool push = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification preferences')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('In-app notifications'),
            value: inApp,
            onChanged: (value) => setState(() => inApp = value),
          ),
          SwitchListTile(
            title: const Text('Push notifications'),
            value: push,
            onChanged: (value) => setState(() => push = value),
          ),
        ],
      ),
    );
  }
}

class SellerEngagementScreen extends StatelessWidget {
  const SellerEngagementScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Seller engagement')),
      );
}

class AnnouncementScreen extends StatelessWidget {
  const AnnouncementScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Announcements')),
      );
}
