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
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
        label: isTe ? 'హోమ్' : 'Home',
      ),
      NavigationDestination(
        icon: const Icon(Icons.history_rounded),
        selectedIcon: const Icon(Icons.history_toggle_off_rounded),
        label: isTe ? 'హిస్టరీ' : 'History',
      ),
      const NavigationDestination(
        icon: Icon(Icons.smart_toy_outlined),
        selectedIcon: Icon(Icons.smart_toy_rounded),
        label: 'ASKODOX',
      ),
      NavigationDestination(
        icon: const Icon(Icons.notifications_none_rounded),
        selectedIcon: const Icon(Icons.notifications_rounded),
        label: isTe ? 'యాక్టివిటీ' : 'Activity',
      ),
      NavigationDestination(
        icon: const Icon(Icons.person_outline_rounded),
        selectedIcon: const Icon(Icons.person_rounded),
        label: isTe ? 'ప్రొఫైల్' : 'Profile',
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
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _go,
                indicatorColor: const Color(0xFFE3F6E8),
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

      return Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        body: shell,
        bottomNavigationBar: NavigationBar(
          height: 72,
          backgroundColor: Colors.white,
          indicatorColor: const Color(0xFFE3F6E8),
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: destinations,
        ),
      );
    });
  }

  void _go(int index) => shell.goBranch(
        index,
        initialLocation: index == shell.currentIndex,
      );
}
