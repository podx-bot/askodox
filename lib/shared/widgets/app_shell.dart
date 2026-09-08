import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/app_settings_provider.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = Localizations.localeOf(context);
    final isTe = locale.languageCode == 'te';
    final languageLabel = locale.languageCode.toUpperCase();

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      return Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF10162A),
          elevation: 0,
          centerTitle: true,
          title: const Text(
            'ASKODOX',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              tooltip: isTe ? 'భాష మార్చండి' : 'Change language',
              onSelected: (code) =>
                  ref.read(appSettingsProvider.notifier).setLocale(Locale(code)),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'en', child: Text('English')),
                PopupMenuItem(value: 'te', child: Text('తెలుగు')),
                PopupMenuItem(value: 'hi', child: Text('हिन्दी')),
                PopupMenuItem(value: 'or', child: Text('ଓଡ଼ିଆ')),
              ],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.language_rounded, size: 20),
                    const SizedBox(width: 5),
                    Text(
                      languageLabel,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        drawer: _AskodoxDrawer(
          isTe: isTe,
          currentBranch: shell.currentIndex,
          onBranch: (index) {
            Navigator.of(context).pop();
            shell.goBranch(index, initialLocation: index == shell.currentIndex);
          },
          onRoute: (route) {
            Navigator.of(context).pop();
            context.go(route);
          },
        ),
        body: wide
            ? Row(
                children: [
                  SafeArea(
                    top: false,
                    child: NavigationRail(
                      backgroundColor: Colors.white,
                      extended: constraints.maxWidth >= 1080,
                      selectedIndex: _visualIndex(shell.currentIndex),
                      onDestinationSelected: (index) => _goVisual(index),
                      indicatorColor: const Color(0xFFE8EAFB),
                      destinations: [
                        NavigationRailDestination(
                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                          selectedIcon: const Icon(Icons.chat_bubble_rounded),
                          label: Text(isTe ? 'చాట్స్' : 'Chats'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.auto_awesome_outlined),
                          selectedIcon: const Icon(Icons.auto_awesome_rounded),
                          label: Text(isTe ? 'అడగండి' : 'Ask'),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.notifications_none_rounded),
                          selectedIcon: const Icon(Icons.notifications_rounded),
                          label: Text(isTe ? 'యాక్టివిటీ' : 'Activity'),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 1, color: Color(0xFFE7ECF4)),
                  Expanded(child: shell),
                ],
              )
            : shell,
        bottomNavigationBar: wide
            ? null
            : _PrimaryBottomBar(
                selectedIndex: _visualIndex(shell.currentIndex),
                isTe: isTe,
                onSelected: _goVisual,
              ),
      );
    });
  }

  int _visualIndex(int branchIndex) {
    if (branchIndex == 1) return 1;
    if (branchIndex == 3) return 2;
    return 0;
  }

  void _goVisual(int visualIndex) {
    final branchIndex = switch (visualIndex) {
      1 => 1,
      2 => 3,
      _ => 0,
    };
    shell.goBranch(
      branchIndex,
      initialLocation: branchIndex == shell.currentIndex,
    );
  }
}

class _PrimaryBottomBar extends StatelessWidget {
  const _PrimaryBottomBar({
    required this.selectedIndex,
    required this.isTe,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool isTe;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        height: 78,
        decoration: const BoxDecoration(
          color: Color(0xFF10162A),
          boxShadow: [
            BoxShadow(
              blurRadius: 16,
              offset: Offset(0, -3),
              color: Color(0x22000000),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _BottomItem(
                selected: selectedIndex == 0,
                icon: Icons.chat_bubble_outline_rounded,
                selectedIcon: Icons.chat_bubble_rounded,
                label: isTe ? 'చాట్స్' : 'Chats',
                onTap: () => onSelected(0),
              ),
            ),
            Expanded(
              child: _AskBottomItem(
                selected: selectedIndex == 1,
                label: isTe ? 'అడగండి' : 'Ask',
                onTap: () => onSelected(1),
              ),
            ),
            Expanded(
              child: _BottomItem(
                selected: selectedIndex == 2,
                icon: Icons.notifications_none_rounded,
                selectedIcon: Icons.notifications_rounded,
                label: isTe ? 'యాక్టివిటీ' : 'Activity',
                onTap: () => onSelected(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Colors.white : const Color(0xFFD6DAE5);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(selected ? selectedIcon : icon, color: color, size: 25),
          const SizedBox(height: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AskBottomItem extends StatelessWidget {
  const _AskBottomItem({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? Colors.white : const Color(0xFF6C63FF),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 12,
                  color: Color(0x556C63FF),
                ),
              ],
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              color: selected ? const Color(0xFF4D46C8) : Colors.white,
              size: 25,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _AskodoxDrawer extends StatelessWidget {
  const _AskodoxDrawer({
    required this.isTe,
    required this.currentBranch,
    required this.onBranch,
    required this.onRoute,
  });

  final bool isTe;
  final int currentBranch;
  final ValueChanged<int> onBranch;
  final ValueChanged<String> onRoute;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 14),
              child: Text(
                'ASKODOX',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.3,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              selected: currentBranch == 0,
              leading: const Icon(Icons.home_outlined),
              title: Text(isTe ? 'హోమ్' : 'Home'),
              onTap: () => onBranch(0),
            ),
            ListTile(
              selected: currentBranch == 2,
              leading: const Icon(Icons.history_rounded),
              title: Text(isTe ? 'హిస్టరీ' : 'History'),
              onTap: () => onBranch(2),
            ),
            ListTile(
              selected: currentBranch == 4,
              leading: const Icon(Icons.person_outline_rounded),
              title: Text(isTe ? 'ప్రొఫైల్' : 'Profile'),
              onTap: () => onBranch(4),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(isTe ? 'దగ్గరలో' : 'Nearby'),
              onTap: () => onRoute('/nearby'),
            ),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: Text(isTe ? 'సెట్టింగ్స్' : 'Settings'),
              onTap: () => onRoute('/notification-preferences'),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: Text(isTe ? 'ప్రైవసీ' : 'Privacy'),
              onTap: () => onRoute('/privacy'),
            ),
          ],
        ),
      ),
    );
  }
}
