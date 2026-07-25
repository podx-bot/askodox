import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'features/analytics/application/analytics_providers.dart';
import 'features/analytics/domain/analytics_models.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: _AnalyticsBootstrap(child: PodxApp())));
}

class _AnalyticsBootstrap extends ConsumerStatefulWidget {
  const _AnalyticsBootstrap({required this.child});
  final Widget child;
  @override
  ConsumerState<_AnalyticsBootstrap> createState() => _AnalyticsBootstrapState();
}

class _AnalyticsBootstrapState extends ConsumerState<_AnalyticsBootstrap> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(analyticsServiceProvider).record(
          AnalyticsEvent(type: AnalyticsEventType.appOpened, occurredAt: DateTime.now()),
        ));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
