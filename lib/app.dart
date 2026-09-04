import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/brand/brand_config.dart';
import 'config/router/app_router.dart';
import 'config/theme/app_theme.dart';
import 'config/theme/askodox_design_tokens.dart';
import 'core/providers/app_settings_provider.dart';
import 'core/offline/offline_models.dart';
import 'core/providers/offline_providers.dart';
import 'generated/l10n/app_localizations.dart';
import 'shared/widgets/connectivity_banner.dart';

Locale askodoxUiLocale(Locale? requested, Iterable<Locale> supportedLocales) {
  final supported = supportedLocales.toList(growable: false);
  if (supported.isEmpty) return const Locale('en');
  if (requested == null) return supported.first;

  for (final locale in supported) {
    if (locale.languageCode == requested.languageCode) return locale;
  }

  for (final locale in supported) {
    if (locale.languageCode == 'en') return locale;
  }

  return supported.first;
}

class PodxApp extends ConsumerWidget {
  const PodxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: BrandConfig.displayName,
      onGenerateTitle: (_) => BrandConfig.displayName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localeResolutionCallback: (locale, supportedLocales) =>
          askodoxUiLocale(locale, supportedLocales),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => _StartupGate(
        child: ConnectivityBanner(child: child ?? const SizedBox.shrink()),
      ),
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
        color: AskodoxDesignTokens.ink,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, color: AskodoxDesignTokens.violet100, size: 44),
              SizedBox(height: 14),
              Text(
                BrandConfig.displayName,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 2),
              ),
              SizedBox(height: 16),
              CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }
    return widget.child;
  }
}
