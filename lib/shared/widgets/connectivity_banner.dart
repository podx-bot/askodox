import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/offline/offline_models.dart';
import '../../core/providers/offline_providers.dart';
import '../../generated/l10n/app_localizations.dart';

class ConnectivityBanner extends ConsumerStatefulWidget { const ConnectivityBanner({required this.child, super.key}); final Widget child; @override ConsumerState<ConnectivityBanner> createState() => _ConnectivityBannerState(); }
class _ConnectivityBannerState extends ConsumerState<ConnectivityBanner> {
  bool dismissed = false;
  @override Widget build(BuildContext context) { final status = ref.watch(connectivityStatusProvider).valueOrNull ?? ConnectivityStatus.unknown; final visible = !dismissed && status != ConnectivityStatus.online; final l10n = AppLocalizations.of(context)!; return Column(children: [if (visible) Material(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: SafeArea(bottom: false, child: Row(children: [const SizedBox(width: 12), Icon(status == ConnectivityStatus.offline ? Icons.cloud_off : Icons.sync, size: 20), const SizedBox(width: 8), Expanded(child: Text(status == ConnectivityStatus.offline ? l10n.offlineCopy : l10n.connectionLimited)), TextButton(onPressed: () => ref.read(connectivityServiceProvider).setStatus(ConnectivityStatus.reconnecting), child: Text(l10n.retry)), TextButton(onPressed: () => context.push('/sync-status'), child: Text(l10n.syncStatus)), IconButton(tooltip: l10n.dismiss, onPressed: () => setState(() => dismissed = true), icon: const Icon(Icons.close))]))), Expanded(child: widget.child)]); }
}
