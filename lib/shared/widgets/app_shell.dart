import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final isTe = Localizations.localeOf(context).languageCode == 'te';
    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: const Icon(Icons.chat_bubble_outline_rounded),
        selectedIcon: const Icon(Icons.chat_bubble_rounded),
        label: isTe ? 'చాట్స్' : 'Chats',
      ),
      NavigationDestination(
        icon: const Icon(Icons.auto_awesome_outlined),
        selectedIcon: const Icon(Icons.auto_awesome_rounded),
        label: isTe ? 'అడగండి' : 'Ask',
      ),
      NavigationDestination(
        icon: const Icon(Icons.notifications_none_rounded),
        selectedIcon: const Icon(Icons.notifications_rounded),
        label: isTe ? 'యాక్టివిటీ' : 'Activity',
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      if (wide) {
        return Scaffold(
          backgroundColor: const Color(0xFFF7FAFF),
          body: Row(children: [
            SafeArea(
              child: NavigationRail(
                backgroundColor: Colors.white,
                extended: constraints.maxWidth >= 1080,
                selectedIndex: _visualIndex(shell.currentIndex),
                onDestinationSelected: (index) => _goVisual(index),
                indicatorColor: const Color(0xFFE8EAFB),
                destinations: destinations
                    .map((item) => NavigationRailDestination(
                          icon: item.icon,
                          selectedIcon: item.selectedIcon,
                          label: Text(item.label),
                        ))
                    .toList(),
              ),
            ),
            const VerticalDivider(width: 1, color: Color(0xFFE7ECF4)),
            Expanded(child: shell),
          ]),
        );
      }

      const navBackground = Color(0xFF10162A);
      const navForeground = Colors.white;
      const navMuted = Color(0xFFD6DAE5);

      return Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        body: shell,
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 76,
            backgroundColor: navBackground,
            indicatorColor: const Color(0xFF1B2342),
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
              return IconThemeData(
                color: states.contains(WidgetState.selected) ? navForeground : navMuted,
                size: 25,
              );
            }),
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
              return TextStyle(
                color: states.contains(WidgetState.selected) ? navForeground : navMuted,
                fontSize: 12,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w600,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: _visualIndex(shell.currentIndex),
            onDestinationSelected: (index) => _goVisual(index),
            destinations: destinations,
          ),
        ),
      );
    });
  }

  // Keep the existing router branches intact while presenting only the three
  // primary ASKODOX actions. Secondary Home/History/Profile destinations move
  // out of the primary navigation and remain reachable by routes/menu links.
  int _visualIndex(int branchIndex) {
    if (branchIndex == 1) return 1; // Ask (/search)
    if (branchIndex == 3) return 2; // Activity (/alerts)
    return 0; // Chats/default
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
