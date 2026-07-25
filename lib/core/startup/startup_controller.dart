import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../offline/offline_models.dart';
import '../offline/offline_services.dart';

class StartupController extends StateNotifier<StartupState> {
  StartupController(this.connectivity) : super(const StartupState(StartupPhase.initializing));
  final ConnectivityService connectivity;
  Future<void> initialize({Future<void> Function()? restoreSession, Future<void> Function()? restorePreferences}) async {
    final stopwatch = Stopwatch()..start();
    try { state = const StartupState(StartupPhase.restoringSession); await (restoreSession?.call() ?? Future<void>.value()); state = const StartupState(StartupPhase.loadingPreferences); await (restorePreferences?.call() ?? Future<void>.value()); final status = await connectivity.check(); state = StartupState(status == ConnectivityStatus.online ? StartupPhase.ready : StartupPhase.offlineReady, elapsed: stopwatch.elapsed); } catch (error) { state = StartupState(StartupPhase.recoverableError, message: '$error', elapsed: stopwatch.elapsed); }
  }
}
