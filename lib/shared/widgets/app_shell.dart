import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../generated/l10n/app_localizations.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final destinations = [
      NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: strings.home),
      NavigationDestination(icon: const Icon(Icons.search), label: strings.search),
      NavigationDestination(icon: const Icon(Icons.favorite_outline), selectedIcon: const Icon(Icons.favorite), label: strings.watchlist),
      const NavigationDestination(icon: Icon(Icons.notifications_outlined), selectedIcon: Icon(Icons.notifications), label: 'Alerts'),
      NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: strings.profile),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      if (wide) {
        return Scaffold(
          body: Row(children: [
            SafeArea(
              child: NavigationRail(
                extended: constraints.maxWidth >= 1080,
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _go,
                destinations: destinations
                    .map((item) => NavigationRailDestination(icon: item.icon, selectedIcon: item.selectedIcon, label: Text(item.label)))
                    .toList(),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ]),
        );
      }
      return Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
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
