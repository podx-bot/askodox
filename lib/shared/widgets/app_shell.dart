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

      const navForeground = Color(0xFF17223B);
      const navMuted = Color(0xFF667085);

      return Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        body: shell,
        bottomNavigationBar: NavigationBarTheme(
          data: NavigationBarThemeData(
            height: 76,
            backgroundColor: Colors.white,
            indicatorColor: const Color(0xFFE3F6E8),
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
                fontSize: 11,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w600,
              );
            }),
          ),
          child: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: _go,
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
