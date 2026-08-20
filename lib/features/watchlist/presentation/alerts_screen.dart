import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/brand/brand_config.dart';
import '../../../config/theme/askodox_design_tokens.dart';
import '../application/watchlist_providers.dart';

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      key: const Key('askodoxAlertsScreen'),
      appBar: AppBar(
        title: const Text('ASKODOX Alerts'),
        actions: [
          IconButton(
            tooltip: 'Notification preferences',
            onPressed: () => context.push('/notification-preferences'),
            icon: const Icon(Icons.tune_rounded),
          ),
          IconButton(
            tooltip: 'Demo automation',
            onPressed: () => context.push('/alert-simulator'),
            icon: const Icon(Icons.science_outlined),
          ),
        ],
      ),
      body: alerts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 92,
                      height: 92,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: AskodoxDesignTokens.actionGradient,
                        boxShadow: [
                          AskodoxDesignTokens.glow(
                            AskodoxDesignTokens.electricBlue,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.notifications_none_rounded,
                        size: 42,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'No alerts yet',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${BrandConfig.displayName} will surface useful nearby updates here. Watch a product, then try Demo automation.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: colors.onSurfaceVariant,
                            height: 1.45,
                          ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final a = alerts[i];
                return Dismissible(
                  key: ValueKey(a.id),
                  onDismissed: (_) => ref.read(alertsProvider.notifier).delete(a.id),
                  child: Card(
                    color: a.isRead
                        ? null
                        : colors.primaryContainer.withValues(alpha: .20),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(14),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: AskodoxDesignTokens.actionGradient,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          a.image,
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                      title: Text(
                        _label(a.type.name),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${a.productName}\n${a.sellerName} · ₹${a.price.toStringAsFixed(0)} · ${a.distanceKm.toStringAsFixed(1)} km · just now',
                        ),
                      ),
                      isThreeLine: true,
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'read') {
                            ref.read(alertsProvider.notifier).read(a.id);
                          }
                          if (v == 'delete') {
                            ref.read(alertsProvider.notifier).delete(a.id);
                          }
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
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'read', child: Text('Mark as read')),
                          PopupMenuItem(value: 'mute', child: Text('Mute product')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                      onTap: () {
                        ref.read(alertsProvider.notifier).read(a.id);
                        context.push('/product/${a.productId}');
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _label(String v) => v
      .replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[0]!.toLowerCase()}')
      .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());
}
