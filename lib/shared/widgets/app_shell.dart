import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/brand/brand_config.dart';
import '../../generated/l10n/app_localizations.dart';
import 'askodox_brand_mark.dart';

class AppShell extends StatelessWidget {
  const AppShell({required this.shell, super.key});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final destinations = [
      NavigationDestination(
        key: const Key('askodoxNavHome'),
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
        label: strings.home,
      ),
      NavigationDestination(
        key: const Key('askodoxNavSearch'),
        icon: const Icon(Icons.search_rounded),
        selectedIcon: const Icon(Icons.travel_explore_rounded),
        label: strings.search,
      ),
      NavigationDestination(
        key: const Key('askodoxNavWatchlist'),
        icon: const Icon(Icons.favorite_outline_rounded),
        selectedIcon: const Icon(Icons.favorite_rounded),
        label: strings.watchlist,
      ),
      const NavigationDestination(
        key: Key('askodoxNavAlerts'),
        icon: Icon(Icons.notifications_outlined),
        selectedIcon: Icon(Icons.notifications_rounded),
        label: 'Alerts',
      ),
      NavigationDestination(
        key: const Key('askodoxNavProfile'),
        icon: const Icon(Icons.person_outline_rounded),
        selectedIcon: const Icon(Icons.person_rounded),
        label: strings.profile,
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 720;
      if (wide) {
        return Scaffold(
          body: Row(children: [
            SafeArea(
              child: NavigationRail(
                extended: constraints.maxWidth >= 1080,
                leading: const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: AskodoxBrandMark(
                    size: 48,
                    showWordmark: true,
                    subtitle: BrandConfig.tagline,
                  ),
                ),
                selectedIndex: shell.currentIndex,
                onDestinationSelected: _go,
                destinations: destinations
                    .map(
                      (item) => NavigationRailDestination(
                        icon: item.icon,
                        selectedIcon: item.selectedIcon,
                        label: Text(item.label),
                      ),
                    )
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
        bottomNavigationBar: SafeArea(
          top: false,
          child: NavigationBar(
            key: const Key('askodoxPrimaryNavigation'),
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: destinations,
          ),
        ),
      );
    });
  }

  void _go(int index) => shell.goBranch(
        index,
        initialLocation: index == shell.currentIndex,
      );
}
