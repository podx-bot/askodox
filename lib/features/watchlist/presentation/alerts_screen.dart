import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../application/watchlist_providers.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final te = ref.watch(appSettingsProvider).locale?.languageCode == 'te';

    return Scaffold(
      appBar: AppBar(
        title: Text(te ? 'స్మార్ట్ అలర్ట్స్' : 'Smart alerts'),
        actions: [
          IconButton(
            tooltip: te ? 'నోటిఫికేషన్ ప్రాధాన్యతలు' : 'Notification preferences',
            onPressed: () => context.push('/notification-preferences'),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: te ? 'డెమో ఆటోమేషన్' : 'Demo automation',
            onPressed: () => context.push('/alert-simulator'),
            icon: const Icon(Icons.science_outlined),
          ),
        ],
      ),
      body: alerts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.notifications_none, size: 64),
                  Text(te ? 'ఇంకా అలర్ట్స్ లేవు' : 'No alerts yet'),
                  Text(te
                      ? 'ఒక వస్తువును వాచ్ చేసి, తర్వాత డెమో ఆటోమేషన్ ప్రయత్నించండి.'
                      : 'Watch a product, then try Demo automation.'),
                ],
              ),
            )
          : ListView.builder(
              itemCount: alerts.length,
              itemBuilder: (context, i) {
                final a = alerts[i];
                return Dismissible(
                  key: ValueKey(a.id),
                  onDismissed: (_) => ref.read(alertsProvider.notifier).delete(a.id),
                  child: ListTile(
                    tileColor: a.isRead
                        ? null
                        : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .3),
                    leading: CircleAvatar(child: Text(a.image)),
                    title: Text(
                      _label(a.type.name, te),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '${a.productName}\n${a.sellerName} · ₹${a.price.toStringAsFixed(0)} · ${a.distanceKm.toStringAsFixed(1)} km · ${te ? 'ఇప్పుడే' : 'just now'}',
                    ),
                    isThreeLine: true,
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'read') ref.read(alertsProvider.notifier).read(a.id);
                        if (v == 'delete') ref.read(alertsProvider.notifier).delete(a.id);
                        if (v == 'mute') {
                          final item = ref
                              .read(watchlistProvider)
                              .where((e) => e.productId == a.productId)
                              .firstOrNull;
                          if (item != null) {
                            ref.read(watchlistProvider.notifier).update(
                                  item.copyWith(alertsEnabled: false),
                                );
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'read',
                          child: Text(te ? 'చదివినట్లు గుర్తించు' : 'Mark as read'),
                        ),
                        PopupMenuItem(
                          value: 'mute',
                          child: Text(te ? 'ఈ వస్తువు అలర్ట్స్ ఆపు' : 'Mute product'),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(te ? 'తొలగించు' : 'Delete'),
                        ),
                      ],
                    ),
                    onTap: () {
                      ref.read(alertsProvider.notifier).read(a.id);
                      context.push('/product/${a.productId}');
                    },
                  ),
                );
              },
            ),
    );
  }

  String _label(String value, bool te) {
    if (te) {
      return switch (value) {
        'priceDrop' => 'ధర తగ్గింది',
        'backInStock' => 'మళ్లీ స్టాక్‌లోకి వచ్చింది',
        'nearbyMatch' => 'దగ్గరలో మ్యాచ్ దొరికింది',
        'offer' => 'ఆఫర్',
        _ => 'అలర్ట్',
      };
    }
    return value
        .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[0]!.toLowerCase()}')
        .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());
  }
}
