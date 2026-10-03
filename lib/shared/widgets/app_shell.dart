import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/application/conversation_archive.dart';
import '../../features/location/application/location_controller.dart';
import '../../features/location/domain/geo_models.dart';
import '../../features/notifications/application/askodox_notifications.dart';
import '../../config/theme/app_theme.dart';
import '../../core/providers/app_settings_provider.dart';
import '../../features/companion/askodox_companion.dart';
import '../../features/companion/companion_floating.dart';
import '../../features/companion/companion_hub.dart';

const _navInk = Color(0xFF10204A);
const _navAccent = Color(0xFF4F46FF);

/// The customer shell. Every bottom item has ONE distinct purpose:
/// Home (ask ASKODOX) · Explore (past conversations and saved options) ·
/// centre companion avatar (its actions: voice, chat, camera, photos,
/// video, files, location) · Orders (what happened to my requests) ·
/// Profile (me, roles, settings). The header bell opens Orders too.
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
      // The floating bubble service may only be (re)started while ASKODOX
      // is on screen -- e.g. right after the overlay permission was granted.
      unawaited(ref.read(askodoxBubbleProvider.notifier).sync());
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
    final lang = Localizations.localeOf(context).languageCode;
    final isTe = lang == 'te';
    final locationState = ref.watch(locationControllerProvider);
    final locationLabel = locationState.headerLocation ?? (isTe ? 'లొకేషన్ ఎంచుకోండి' : 'Choose location');
    final updates = ref.watch(askodoxUpdatesProvider).valueOrNull?.length ?? 0;
    // A companion action from outside Main Chat continues the SAME chat.
    void companionAction(AskodoxHubAction action) {
      shell.goBranch(0, initialLocation: true);
      ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.action(action);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FBFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navInk,
        elevation: 0,
        automaticallyImplyLeading: false,
        centerTitle: false,
        titleSpacing: 12,
        // Header: ASKODOX · where I am · my language · notifications. Home
        // itself stays clean -- no shortcut grid.
        title: Row(children: [
          const Expanded(
            child: Text('ASKODOX',
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: TextStyle(color: _navInk, fontWeight: FontWeight.w900, letterSpacing: 1.1)),
          ),
          InkWell(
            key: const Key('askodoxLocationChip'),
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.push('/location'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                // Stale = the last detected place, not a fresh fix (GPS off,
                // permission revoked): shown in amber with a tooltip.
                // GPS place (crosshair) vs a place the user picked (pin) vs
                // an old detected place (amber, stale) -- never confused.
                Builder(builder: (context) {
                  final gps = locationState.defaultLocation?.type == SavedLocationType.currentLocation;
                  final source = locationState.stale
                      ? 'stale'
                      : gps
                          ? 'gps'
                          : (locationState.hasPlace ? 'manual' : 'none');
                  return Tooltip(
                    message: switch (source) {
                      'stale' => locationState.message ?? 'Last detected place',
                      'gps' => isTe ? 'ఫోన్ GPS ప్రకారం ప్రస్తుత స్థానం' : 'Current location (phone GPS)',
                      'manual' => isTe ? 'మీరు ఎంచుకున్న స్థానం' : 'Place you chose',
                      _ => '',
                    },
                    child: Icon(
                        switch (source) {
                          'stale' => Icons.location_disabled_rounded,
                          'gps' => Icons.my_location_rounded,
                          _ => Icons.location_on_rounded,
                        },
                        key: ValueKey('askodoxLocationSource-$source'),
                        size: 18,
                        color: source == 'stale' ? const Color(0xFFB26A00) : const Color(0xFF1769FF)),
                  );
                }),
                const SizedBox(width: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 104),
                  child: Text(
                    locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _navInk, fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: _navInk),
              ]),
            ),
          ),
          PopupMenuButton<String>(
            key: const Key('askodoxLanguageChip'),
            tooltip: isTe ? 'భాష' : 'Language',
            onSelected: (code) => ref.read(appSettingsProvider.notifier).setLocale(Locale(code)),
            itemBuilder: (context) => [
              for (final (code, name) in const [('en', 'English'), ('te', 'తెలుగు'), ('hi', 'हिन्दी'), ('or', 'ଓଡ଼ିଆ')])
                PopupMenuItem(value: code, key: ValueKey('askodoxLanguage-$code'), child: Text(name)),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.language_rounded, size: 18, color: _navInk),
                const SizedBox(width: 2),
                Text(
                  switch (lang) { 'te' => 'తెలుగు', 'hi' => 'हिन्दी', 'or' => 'ଓଡ଼ିଆ', _ => 'EN' },
                  style: const TextStyle(color: _navInk, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ]),
            ),
          ),
          IconButton(
            key: const Key('askodoxHeaderBell'),
            tooltip: isTe ? 'నోటిఫికేషన్లు' : 'Notifications',
            visualDensity: VisualDensity.compact,
            onPressed: () => shell.goBranch(3, initialLocation: true),
            icon: Badge(
              isLabelVisible: updates > 0,
              label: Text(updates > 9 ? '9+' : '$updates'),
              child: const Icon(Icons.notifications_none_rounded, color: _navInk),
            ),
          ),
        ]),
      ),
      body: Stack(children: [
        // The customer shell is a light design (white header, light
        // background). The app runs ThemeMode.dark for other routes, whose
        // white text was invisible here (Orders looked blank -- APK 1274):
        // every tab inside the shell uses the light theme it is drawn on.
        Positioned.fill(
          child: Theme(
            data: AppTheme.light,
            // Material re-applies the light text style (the inherited one is
            // the dark theme's white).
            child: Material(type: MaterialType.transparency, child: shell),
          ),
        ),
        // Optional floating companion on the other ASKODOX screens (Main
        // Chat already shows it): the same assistant, same conversation.
        if (shell.currentIndex != 0)
          Positioned.fill(
            child: AskodoxInAppFloatingCompanion(
              lang: lang,
              onAction: companionAction,
              bottomInset: 8,
              // "Ask about this": the screen the user is on becomes the question.
              onAskAboutThis: () {
                final prompt = switch (shell.currentIndex) {
                  2 => isTe ? 'నా సేవ్ చేసిన ఎంపికలు, చరిత్ర గురించి సహాయం చేయండి' : 'Help me with my saved options and history',
                  3 => isTe ? 'నా ఆర్డర్లు, అప్‌డేట్‌ల గురించి చెప్పండి' : 'Tell me about my orders and updates',
                  4 => isTe ? 'నా ప్రొఫైల్, సెట్టింగ్‌ల గురించి సహాయం చేయండి' : 'Help me with my profile and settings',
                  _ => isTe ? 'ఈ స్క్రీన్ గురించి సహాయం చేయండి' : 'Help me with this screen',
                };
                shell.goBranch(0, initialLocation: true);
                ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(prompt);
              },
            ),
          ),
      ]),
      bottomNavigationBar: _PrimaryBottomBar(
        currentBranch: shell.currentIndex,
        isTe: isTe,
        onHome: () => shell.goBranch(0, initialLocation: true),
        onHistory: () => shell.goBranch(2, initialLocation: true),
        onCompanion: () {
          // Listening: a tap stops it. Otherwise open / close the
          // companion's actions on Main Chat.
          if (ref.read(askodoxCompanionLiveProvider).listening) {
            companionAction(AskodoxHubAction.voice);
            return;
          }
          final hub = ref.read(askodoxCompanionHubOpenProvider.notifier);
          final open = shell.currentIndex == 0 ? !hub.state : true;
          shell.goBranch(0, initialLocation: true);
          hub.state = open;
        },
        onCompanionClose: () => ref.read(askodoxCompanionHubOpenProvider.notifier).state = false,
        onUpdates: () => shell.goBranch(3, initialLocation: true),
        onProfile: () => shell.goBranch(4, initialLocation: true),
      ),
    );
  }
}

class _PrimaryBottomBar extends ConsumerWidget {
  const _PrimaryBottomBar({
    required this.currentBranch,
    required this.isTe,
    required this.onHome,
    required this.onHistory,
    required this.onCompanion,
    required this.onCompanionClose,
    required this.onUpdates,
    required this.onProfile,
  });
  final int currentBranch;
  final bool isTe;
  final VoidCallback onHome, onHistory, onCompanion, onCompanionClose, onUpdates, onProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(askodoxCompanionLiveProvider);
    final hubOpen = ref.watch(askodoxCompanionHubOpenProvider);
    return SafeArea(top: false, child: Container(
      height: 76,
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE6ECF5)))),
      child: Row(children: [
        _item('askodoxNavHome', currentBranch == 0, Icons.home_outlined, Icons.home_rounded, isTe ? 'హోమ్' : 'Home', onHome),
        // Past conversations, saved options and requests to revisit.
        _item('askodoxNavHistory', currentBranch == 2, Icons.explore_outlined, Icons.explore_rounded, isTe ? 'ఎక్స్‌ప్లోర్' : 'Explore', onHistory),
        // The ONE companion entry: its face (not a microphone). Tap = open
        // its actions (or stop listening); double tap = close.
        Expanded(child: Semantics(
          button: true,
          label: isTe ? 'ASKODOX సహచరుడు' : 'ASKODOX companion',
          child: GestureDetector(
            key: const Key('askodoxNavSpeak'),
            onTap: onCompanion,
            onDoubleTap: onCompanionClose,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(
                      color: live.listening ? const Color(0xFFE5484D) : (hubOpen ? const Color(0xFF6C4DFF) : const Color(0xFFD9D2FF)),
                      width: live.listening || hubOpen ? 3 : 2),
                  boxShadow: const [BoxShadow(color: Color(0x336C4DFF), blurRadius: 12)],
                ),
                child: ClipOval(
                  child: IgnorePointer(child: AskodoxCompanion(key: const Key('askodoxNavCompanion'), mood: live.mood, size: 54)),
                ),
              ),
            ]),
          ),
        )),
        _item('askodoxNavUpdates', currentBranch == 3, Icons.receipt_long_outlined, Icons.receipt_long_rounded, isTe ? 'ఆర్డర్లు' : 'Orders', onUpdates),
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
