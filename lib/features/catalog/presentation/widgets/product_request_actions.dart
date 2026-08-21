import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../buyer/application/buyer_providers.dart';
import '../../../buyer/domain/entities/buyer_models.dart';
import '../../../watchlist/application/watchlist_providers.dart';
import '../../../watchlist/domain/watchlist_models.dart';

class ProductRequestActions extends ConsumerWidget {
  const ProductRequestActions({this.compact = false, super.key});

  final bool compact;

  static const _productId = 'requested-product';
  static const _productName = 'Requested product';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watchlist = ref.watch(watchlistProvider);
    WatchlistItem? existing;
    for (final item in watchlist) {
      if (item.productId == _productId) {
        existing = item;
        break;
      }
    }

    void show(String message) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }

    void saveRequest({bool? watchlisted, bool? notify}) {
      ref.read(buyerRepositoryProvider).saveRequest(
            BuyerProductRequest(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              productName: _productName,
              createdAt: DateTime.now(),
              watchlisted: watchlisted ?? existing != null,
              notify: notify ?? existing?.alertsEnabled ?? false,
            ),
          );
    }

    WatchlistItem newWatchlistItem({required bool alertsEnabled}) =>
        WatchlistItem(
          productId: _productId,
          productName: _productName,
          brand: 'Unknown brand',
          variant: 'Requested item',
          image: '',
          createdAt: DateTime.now(),
          alertsEnabled: alertsEnabled,
          requestStatus: ProductRequestStatus.pending,
        );

    final request = FilledButton.icon(
      key: const Key('productRequestSave'),
      onPressed: () {
        saveRequest();
        show('Product request saved locally.');
      },
      icon: const Icon(Icons.add_shopping_cart),
      label: const Text('Request Product'),
    );

    final upload = OutlinedButton.icon(
      key: const Key('productRequestImage'),
      onPressed: () => context.push('/discover/image'),
      icon: const Icon(Icons.add_a_photo_outlined),
      label: const Text('Add Product Image'),
    );

    final watch = OutlinedButton.icon(
      key: const Key('productRequestWatchlist'),
      onPressed: () {
        if (existing == null) {
          ref.read(watchlistProvider.notifier).add(
                newWatchlistItem(alertsEnabled: false),
              );
          saveRequest(watchlisted: true, notify: false);
          show('Added to watchlist.');
        } else {
          ref.read(watchlistProvider.notifier).remove(_productId);
          saveRequest(watchlisted: false, notify: false);
          show('Removed from watchlist.');
        }
      },
      icon: Icon(existing == null ? Icons.favorite_border : Icons.favorite),
      label: Text(existing == null ? 'Add to Watchlist' : 'In Watchlist'),
    );

    final notificationsEnabled = existing?.alertsEnabled ?? false;
    final notify = OutlinedButton.icon(
      key: const Key('productRequestNotify'),
      onPressed: () {
        if (existing == null) {
          ref.read(watchlistProvider.notifier).add(
                newWatchlistItem(alertsEnabled: true),
              );
          saveRequest(watchlisted: true, notify: true);
          show('Notifications enabled and product added to watchlist.');
          return;
        }

        final updated = existing.copyWith(
          alertsEnabled: !notificationsEnabled,
        );
        ref.read(watchlistProvider.notifier).update(updated);
        saveRequest(
          watchlisted: true,
          notify: !notificationsEnabled,
        );
        show(
          notificationsEnabled
              ? 'Notifications disabled.'
              : 'Notifications enabled.',
        );
      },
      icon: Icon(
        notificationsEnabled
            ? Icons.notifications_active
            : Icons.notifications_active_outlined,
      ),
      label: Text(
        notificationsEnabled ? 'Notifications On' : 'Notify Me',
      ),
    );

    final children = [request, upload, watch, notify];
    return compact
        ? Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: children,
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children
                .expand((widget) => [widget, const SizedBox(height: 10)])
                .toList(),
          );
  }
}
