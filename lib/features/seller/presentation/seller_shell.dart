import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../generated/l10n/app_localizations.dart';

class SellerShell extends StatelessWidget {
  const SellerShell({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context)!;
    final destinations = [
      (strings.sellerDashboard, Icons.dashboard_outlined, '/seller/dashboard'),
      (strings.sellerProducts, Icons.inventory_2_outlined, '/seller/products'),
      (strings.sellerRequests, Icons.campaign_outlined, '/seller/requests'),
      (strings.sellerInsights, Icons.insights_outlined, '/seller/insights'),
      ('Engagement', Icons.campaign_outlined, '/seller/engagement'),
      (strings.sellerProfile, Icons.store_outlined, '/seller/profile'),
      (strings.billing, Icons.workspace_premium_outlined, '/seller/usage'),
    ];
    final location = GoRouterState.of(context).uri.path;
    final matchedIndex = destinations.indexWhere((item) => location.startsWith(item.$3));
    final index = matchedIndex < 0 ? 0 : matchedIndex;
    void navigate(int selected) => context.go(destinations[selected].$3);
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= 900;
      final content = wide
          ? Row(children: [
              NavigationRail(selectedIndex: index, onDestinationSelected: navigate, labelType: NavigationRailLabelType.all, destinations: [for (final item in destinations) NavigationRailDestination(icon: Icon(item.$2), label: Text(item.$1))]),
              const VerticalDivider(width: 1),
              Expanded(child: child),
            ])
          : child;
      return Scaffold(
        body: content,
        bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: index, onDestinationSelected: navigate, destinations: [for (final item in destinations) NavigationDestination(icon: Icon(item.$2), label: item.$1)]),
      );
    });
  }
}
