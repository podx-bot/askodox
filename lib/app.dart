import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/router/app_router.dart';
import 'config/theme/app_theme.dart';
import 'core/providers/app_settings_provider.dart';
import 'core/offline/offline_models.dart';
import 'core/providers/offline_providers.dart';
import 'generated/l10n/app_localizations.dart';
import 'shared/widgets/connectivity_banner.dart';

class PodxApp extends ConsumerWidget {
  const PodxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => _StartupGate(child: ConnectivityBanner(child: child ?? const SizedBox.shrink())),
    );
  }
}

class _StartupGate extends ConsumerStatefulWidget {
  const _StartupGate({required this.child});
  final Widget child;
  @override
  ConsumerState<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends ConsumerState<_StartupGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(startupControllerProvider.notifier).initialize());
  }

  @override
  Widget build(BuildContext context) {
    final startup = ref.watch(startupControllerProvider);
    final waiting = startup.phase == StartupPhase.initializing ||
        startup.phase == StartupPhase.restoringSession ||
        startup.phase == StartupPhase.loadingPreferences;
    if (waiting) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return widget.child;
  }
}
