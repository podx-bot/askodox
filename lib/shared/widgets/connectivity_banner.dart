import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/offline/offline_models.dart';
import '../../core/providers/offline_providers.dart';
import '../../generated/l10n/app_localizations.dart';

class ConnectivityBanner extends ConsumerStatefulWidget { const ConnectivityBanner({required this.child, super.key}); final Widget child; @override ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState(); }
class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  bool dismissed = false;
  @override Widget build(BuildContext context) {
    final status = ref.watch(connectivityStatusProvider).valueOrNull ?? ConnectivityStatus.unknown;
    final visible = !dismissed && {ConnectivityStatus.offline, ConnectivityStatus.limited, ConnectivityStatus.reconnecting}.contains(status);
    final l10n = AppLocalizations.of(context)!;
    return Column(children: [
      if (visible)
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(children: [
                Icon(status == ConnectivityStatus.offline ? Icons.cloud_off : Icons.sync, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(status == ConnectivityStatus.offline ? l10n.offlineCopy : l10n.connectionLimited, maxLines: 2, overflow: TextOverflow.ellipsis)),
                IconButton(onPressed: () => ref.read(connectivityServiceProvider).setStatus(ConnectivityStatus.reconnecting), icon: const Icon(Icons.refresh), tooltip: l10n.retry),
                IconButton(onPressed: () => context.push('/sync-status'), icon: const Icon(Icons.sync_alt), tooltip: l10n.syncStatus),
                IconButton(onPressed: () => setState(() => dismissed = true), icon: const Icon(Icons.close), tooltip: l10n.dismiss),
              ]),
            ),
          ),
        ),
      Expanded(child: widget.child),
    ]);
  }
}
