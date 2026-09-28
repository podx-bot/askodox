import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/application/conversation_archive.dart';
import '../../features/location/application/location_controller.dart';
import '../../features/notifications/application/askodox_notifications.dart';

const _navInk = Color(0xFF10204A);
const _navAccent = Color(0xFF4F46FF);

/// The customer shell. Every bottom item has ONE distinct purpose:
/// Home (ask ASKODOX) · History (past conversations) · centre mic (talk to
/// ASKODOX now) · Updates (what happened to my requests) · Profile (me,
/// roles, settings). No drawer duplicating these, no second bell.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  Timer? _updatesTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onForeground());
    // While the app is open, new request updates arrive as silent
    // notifications (no push service yet: see CLAUDE.md known issues).
    _updatesTimer = Timer.periodic(const Duration(seconds: 60), (_) => _checkUpdates());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updatesTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final location = ref.read(locationControllerProvider.notifier);
    if (state == AppLifecycleState.resumed) {
      _onForeground();
      // Back in the app: re-read where the phone is now (no prompt) and keep
      // following it -- unless the user picked a place by hand.
      unawaited(location.onResume());
    } else if (state == AppLifecycleState.paused) {
      // No location use in the background.
      unawaited(location.stopFollowing());
    }
  }

  Future<void> _onForeground() async {
    // A tapped notification opens the screen it is about.
    final route = await ref.read(askodoxDeviceNotificationsProvider).consumeLaunchRoute();
    if (mounted && route != null && route.startsWith('/')) {
      route == '/' ? context.go('/') : context.push(route);
    }
    await _checkUpdates();
  }

  Future<void> _checkUpdates() async {
    try {
      await ref.read(askodoxUpdateNotifierProvider).check();
    } catch (_) {
      // Updates are best effort; the app never depends on them.
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    final isTe = Localizations.localeOf(context).languageCode == 'te';
    final locationState = ref.watch(locationControllerProvider);
    final locationLabel = locationState.headerLocation ?? (isTe ? 'లొకేషన్ ఎంచుకోండి' : 'Choose location');
    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navInk,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        title: Row(children: [
          const Expanded(child: Text('ASKODOX', style: TextStyle(color: _navInk, fontWeight: FontWeight.w900, letterSpacing: 1.1))),
          InkWell(
            key: const Key('askodoxLocationChip'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push('/location'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.location_on_rounded, size: 20, color: Color(0xFF1769FF)),
                const SizedBox(width: 3),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _navInk, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _navInk),
              ]),
            ),
          ),
        ]),
      ),
      body: shell,
      bottomNavigationBar: _PrimaryBottomBar(
        currentBranch: shell.currentIndex,
        isTe: isTe,
        onHome: () => shell.goBranch(0, initialLocation: true),
        onHistory: () => shell.goBranch(2, initialLocation: true),
        onSpeak: () {
          ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.voice();
          shell.goBranch(0, initialLocation: true);
        },
        onUpdates: () => shell.goBranch(3, initialLocation: true),
        onProfile: () => shell.goBranch(4, initialLocation: true),
      ),
    );
  }
}

class _PrimaryBottomBar extends StatelessWidget {
  const _PrimaryBottomBar({
    required this.currentBranch,
    required this.isTe,
    required this.onHome,
    required this.onHistory,
    required this.onSpeak,
    required this.onUpdates,
    required this.onProfile,
  });
  final int currentBranch;
  final bool isTe;
  final VoidCallback onHome, onHistory, onSpeak, onUpdates, onProfile;

  @override
  Widget build(BuildContext context) {
    return SafeArea(top: false, child: Container(
      height: 72,
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE6ECF5)))),
      child: Row(children: [
        _item('askodoxNavHome', currentBranch == 0, Icons.home_outlined, Icons.home_rounded, isTe ? 'హోమ్' : 'Home', onHome),
        _item('askodoxNavHistory', currentBranch == 2, Icons.history_rounded, Icons.history_rounded, isTe ? 'చరిత్ర' : 'History', onHistory),
        Expanded(child: Semantics(
          button: true,
          label: isTe ? 'మాట్లాడండి' : 'Speak to ASKODOX',
          child: InkWell(
            key: const Key('askodoxNavSpeak'),
            onTap: onSpeak,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [Color(0xFF1769FF), Color(0xFF713BFF)])),
                child: const Icon(Icons.mic_rounded, color: Colors.white),
              ),
            ]),
          ),
        )),
        _item('askodoxNavUpdates', currentBranch == 3, Icons.notifications_none_rounded, Icons.notifications_rounded, isTe ? 'అప్‌డేట్స్' : 'Updates', onUpdates),
        _item('askodoxNavProfile', currentBranch == 4, Icons.person_outline_rounded, Icons.person_rounded, isTe ? 'ప్రొఫైల్' : 'Profile', onProfile),
      ]),
    ));
  }

  Widget _item(String key, bool selected, IconData icon, IconData selectedIcon, String label, VoidCallback onTap) =>
      Expanded(child: InkWell(
        key: Key(key),
        onTap: onTap,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(selected ? selectedIcon : icon, color: selected ? _navAccent : _navInk, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w800 : FontWeight.w700, color: selected ? _navAccent : _navInk)),
        ]),
      ));
}
