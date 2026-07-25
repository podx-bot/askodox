import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/offline_providers.dart';
import '../../../generated/l10n/app_localizations.dart';
class PerformanceMonitorScreen extends ConsumerWidget { const PerformanceMonitorScreen({super.key}); @override Widget build(BuildContext context, WidgetRef ref) { final l = AppLocalizations.of(context)!; if (kReleaseMode) return Scaffold(body: Center(child: Text(l.developerToolsUnavailable))); final metrics = ref.watch(performanceMonitorProvider).metrics; return Scaffold(appBar: AppBar(title: Text(l.performanceMonitor)), body: ListView(children: [for (final metric in metrics) ListTile(title: Text(metric.name), trailing: Text('${metric.value} ${metric.unit}')), ListTile(title: Text(l.cacheHits), trailing: Text('${ref.watch(cacheRepositoryProvider).hits}')), ListTile(title: Text(l.cacheMisses), trailing: Text('${ref.watch(cacheRepositoryProvider).misses}')), ListTile(title: Text(l.memoryUsagePlaceholder), trailing: const Text('—'))])); } }
