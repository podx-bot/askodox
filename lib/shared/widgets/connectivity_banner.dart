import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/offline/offline_models.dart';
import '../../core/providers/offline_providers.dart';
import '../../generated/l10n/app_localizations.dart';

class ConnectivityBanner extends ConsumerStatefulWidget {
  const ConnectivityBanner({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  bool dismissed = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(connectivityStatusProvider).valueOrNull;
    final degraded = status == ConnectivityStatus.offline ||
        status == ConnectivityStatus.limited ||
        status == ConnectivityStatus.reconnecting;
    final visible = !dismissed && degraded;
    final l10n = AppLocalizations.of(context)!;

    if (!visible) return widget.child;

    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Icon(status == ConnectivityStatus.offline ? Icons.cloud_off : Icons.sync, size: 20),
                  Text(status == ConnectivityStatus.offline ? l10n.offlineCopy : l10n.connectionLimited),
                  TextButton(
                    onPressed: () => ref.read(connectivityServiceProvider).setStatus(ConnectivityStatus.reconnecting),
                    child: Text(l10n.retry),
                  ),
                  TextButton(onPressed: () => context.push('/sync-status'), child: Text(l10n.syncStatus)),
                  IconButton(
                    onPressed: () => setState(() => dismissed = true),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
