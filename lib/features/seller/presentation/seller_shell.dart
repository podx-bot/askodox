import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SellerShell extends StatelessWidget {
  const SellerShell({required this.child, super.key});
  final Widget child;

  static const _destinations = [
    ('Dashboard', Icons.dashboard_outlined, '/seller/dashboard'),
    ('Products', Icons.inventory_2_outlined, '/seller/products'),
    ('Requests', Icons.campaign_outlined, '/seller/requests'),
    ('Insights', Icons.insights_outlined, '/seller/insights'),
    ('Profile', Icons.store_outlined, '/seller/profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final matchedIndex = _destinations.indexWhere((item) => location.startsWith(item.$3));
    final index = matchedIndex < 0 ? 0 : matchedIndex;
    void navigate(int selected) => context.go(_destinations[selected].$3);
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final content = wide
          ? Row(children: [
              NavigationRail(selectedIndex: index, onDestinationSelected: navigate, labelType: NavigationRailLabelType.all, destinations: [for (final item in _destinations) NavigationRailDestination(icon: Icon(item.$2), label: Text(item.$1))]),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ])
          : child;
      return Scaffold(
        body: content,
        bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: index, onDestinationSelected: navigate, destinations: [for (final item in _destinations) NavigationDestination(icon: Icon(item.$2), label: item.$1)]),
      );
    });
  }
}
