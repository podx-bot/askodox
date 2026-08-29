import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers/backend_providers.dart';
import 'core/update/askodox_update_service.dart';
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
  Timer? _sessionTimer;
  bool _updateChecked = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(authSessionProvider.notifier).restore();
      await ref.read(analyticsServiceProvider).record(
            AnalyticsEvent(type: AnalyticsEventType.appOpened, occurredAt: DateTime.now()),
          );
      await _restoreOnboardingIdentity();
    });

    _sessionTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (ref.read(authSessionProvider).user != null) {
        _sessionTimer?.cancel();
        return;
      }
      await _restoreOnboardingIdentity();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _restoreOnboardingIdentity() async {
    if (ref.read(authSessionProvider).user != null) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('askodox.onboarding.complete') != true) return;
    final mobile = prefs.getString('askodox.profile.mobile')?.trim() ?? '';
    final name = prefs.getString('askodox.profile.name')?.trim() ?? '';
    if (mobile.isEmpty || name.isEmpty) return;
    await ref.read(authSessionProvider.notifier).completeOnboarding(
          mobile: mobile,
          displayName: name,
        );
    _sessionTimer?.cancel();
  }

  Future<void> _checkForUpdate() async {
    if (_updateChecked || !AskodoxUpdateService.enabled) return;
    _updateChecked = true;
    try {
      const service = AskodoxUpdateService();
      final result = await service.checkForUpdate();
      final update = result.update;
      if (!mounted || update == null) return;

      final te = Localizations.localeOf(context).languageCode == 'te';
      final install = await showDialog<bool>(
        context: context,
        barrierDismissible: !update.mandatory,
        builder: (dialogContext) => AlertDialog(
          title: Text(te ? 'ASKODOX అప్‌డేట్ అందుబాటులో ఉంది' : 'ASKODOX update available'),
          content: Text(
            te
                ? 'కొత్త వెర్షన్ ${update.version} సిద్ధంగా ఉంది. యాప్‌లోనే అప్‌డేట్ చేసుకోవచ్చు.'
                : 'Version ${update.version} is ready. You can update directly inside ASKODOX.',
          ),
          actions: [
            if (!update.mandatory)
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(te ? 'తర్వాత' : 'Later'),
              ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.system_update_alt_rounded),
              label: Text(te ? 'ఇప్పుడే అప్‌డేట్ చేయండి' : 'Update now'),
            ),
          ],
        ),
      );
      if (install != true || !mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(te ? 'అప్‌డేట్ డౌన్‌లోడ్ అవుతోంది…' : 'Downloading update…')),
      );
      await service.downloadAndInstall(update);
    } catch (_) {
      // Update checks must never block normal ASKODOX usage.
    }
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
