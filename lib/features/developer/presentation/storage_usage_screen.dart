import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/offline/offline_models.dart';
import '../../../core/providers/offline_providers.dart';
import '../../../generated/l10n/app_localizations.dart';

class StorageUsageScreen extends ConsumerStatefulWidget { const StorageUsageScreen({super.key}); @override ConsumerState<StorageUsageScreen> createState() => _StorageUsageScreenState(); }
class _StorageUsageScreenState extends ConsumerState<StorageUsageScreen> {
  late Future<StorageUsage> usage;
  @override void initState() { super.initState(); usage = ref.read(storageManagementProvider).usage(); }
  void reload() => setState(() => usage = ref.read(storageManagementProvider).usage());
  @override Widget build(BuildContext context) { final l = AppLocalizations.of(context)!; return Scaffold(appBar: AppBar(title: Text(l.storageUsage)), body: FutureBuilder<StorageUsage>(future: usage, builder: (context, snapshot) { final value = snapshot.data; if (value == null) return const Center(child: CircularProgressIndicator()); final rows = {l.cachedProducts: value.cachedProducts, l.cachedShopData: value.cachedShops, l.searchHistorySize: value.searchHistory, l.imageCacheSize: value.imageCache, l.analyticsCacheSize: value.analyticsCache, l.pendingSyncSize: value.pendingSync, l.totalLocalStorage: value.total}; return ListView(padding: const EdgeInsets.all(16), children: [for (final row in rows.entries) ListTile(title: Text(row.key), trailing: Text('${row.value} B')), const Divider(), ListTile(title: Text(l.clearSearchHistory), onTap: () async { await ref.read(storageManagementProvider).clearSearchHistory(); reload(); }), ListTile(title: Text(l.clearStaleData), onTap: () async { await ref.read(storageManagementProvider).clearStale(); reload(); }), ListTile(title: Text(l.clearAnalyticsCache), onTap: () async { await ref.read(storageManagementProvider).clearAnalytics(); reload(); }), ListTile(title: Text(l.clearAllLocalData), textColor: Theme.of(context).colorScheme.error, onTap: () => _confirm(context, l))]); })); }
  Future<void> _confirm(BuildContext context, AppLocalizations l) async { final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(l.clearAllLocalData), content: Text(l.clearLocalDataConfirmation), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l.cancel)), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l.clear))])); if (yes == true) { await ref.read(storageManagementProvider).clearAllLocalData(); reload(); } }
}
