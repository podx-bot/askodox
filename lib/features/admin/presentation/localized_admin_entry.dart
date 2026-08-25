import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/admin_controller.dart';
import '../domain/admin_models.dart';

String _t(BuildContext context, String en, String te) =>
    Localizations.localeOf(context).languageCode == 'te' ? te : en;

String _sectionLabel(BuildContext context, AdminSection section) => switch (section) {
      AdminSection.dashboard => _t(context, 'Dashboard', 'డ్యాష్‌బోర్డ్'),
      AdminSection.sellers => _t(context, 'Sellers', 'సెల్లర్లు'),
      AdminSection.catalog => _t(context, 'Catalog', 'కాటలాగ్'),
      AdminSection.productRequests => _t(context, 'Requests', 'రిక్వెస్టులు'),
      AdminSection.searchQuality => _t(context, 'Search quality', 'సెర్చ్ నాణ్యత'),
      AdminSection.moderation => _t(context, 'Moderation', 'మోడరేషన్'),
      AdminSection.support => _t(context, 'Support', 'సపోర్ట్'),
      AdminSection.auditLog => _t(context, 'Audit log', 'ఆడిట్ లాగ్'),
      AdminSection.settings => _t(context, 'Settings', 'సెట్టింగ్స్'),
    };

IconData _sectionIcon(AdminSection section) => switch (section) {
      AdminSection.dashboard => Icons.dashboard_outlined,
      AdminSection.sellers => Icons.store_outlined,
      AdminSection.catalog => Icons.inventory_2_outlined,
      AdminSection.productRequests => Icons.playlist_add_check,
      AdminSection.searchQuality => Icons.manage_search,
      AdminSection.moderation => Icons.gavel_outlined,
      AdminSection.support => Icons.support_agent,
      AdminSection.auditLog => Icons.history,
      AdminSection.settings => Icons.settings_outlined,
    };

class LocalizedAdminLoginScreen extends ConsumerStatefulWidget {
  const LocalizedAdminLoginScreen({super.key});

  @override
  ConsumerState<LocalizedAdminLoginScreen> createState() =>
      _LocalizedAdminLoginScreenState();
}

class _LocalizedAdminLoginScreenState
    extends ConsumerState<LocalizedAdminLoginScreen> {
  AdminRole role = AdminRole.superAdmin;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(Icons.admin_panel_settings,
                        size: 54, color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('ASKODOX Admin',
                        style: Theme.of(context).textTheme.headlineMedium,
                        textAlign: TextAlign.center),
                    Text(
                      _t(context, 'Mock secure access • local data only',
                          'టెస్ట్ సెక్యూర్ యాక్సెస్ • లోకల్ డేటా మాత్రమే'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    DropdownButtonFormField<AdminRole>(
                      isExpanded: true,
                      initialValue: role,
                      decoration: InputDecoration(
                        labelText: _t(context, 'Admin role', 'అడ్మిన్ రోల్'),
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        for (final value in AdminRole.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(value.label,
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => role = value);
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () async {
                        await ref.read(adminControllerProvider.notifier).login(role);
                        if (context.mounted) context.go('/admin/dashboard');
                      },
                      icon: const Icon(Icons.login),
                      label: Text(_t(context, 'Sign in', 'సైన్ ఇన్')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class LocalizedAdminShell extends ConsumerWidget {
  const LocalizedAdminShell({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(adminControllerProvider).user;
    if (user == null) return const LocalizedAdminLoginScreen();
    final allowed = sectionsFor(user.role).toList();
    final location = GoRouterState.of(context).uri.pathSegments.last;
    final current = allowed.indexWhere((e) => e.name == location);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        return Scaffold(
          appBar: AppBar(
            title: Text('ASKODOX Admin • ${user.role.label}'),
            actions: [
              IconButton(
                tooltip: _t(context, 'Analytics and BI', 'అనలిటిక్స్ & BI'),
                onPressed: () => context.push('/admin/analytics'),
                icon: const Icon(Icons.analytics_outlined),
              ),
              IconButton(
                tooltip: _t(context, 'Report builder', 'రిపోర్ట్ బిల్డర్'),
                onPressed: () => context.push('/admin/reports'),
                icon: const Icon(Icons.summarize_outlined),
              ),
              if (!wide)
                PopupMenuButton<AdminSection>(
                  icon: const Icon(Icons.menu),
                  onSelected: (s) => context.go('/admin/${s.name}'),
                  itemBuilder: (_) => [
                    for (final s in allowed)
                      PopupMenuItem(value: s, child: Text(_sectionLabel(context, s))),
                  ],
                ),
              IconButton(
                tooltip: _t(context, 'Sign out', 'సైన్ అవుట్'),
                onPressed: () => context.go('/admin/login'),
                icon: const Icon(Icons.logout),
              ),
            ],
          ),
          body: Row(
            children: [
              if (wide)
                NavigationRail(
                  extended: constraints.maxWidth >= 1150,
                  selectedIndex: current < 0 ? 0 : current,
                  onDestinationSelected: (i) =>
                      context.go('/admin/${allowed[i].name}'),
                  destinations: [
                    for (final section in allowed)
                      NavigationRailDestination(
                        icon: Icon(_sectionIcon(section)),
                        label: Text(_sectionLabel(context, section)),
                      ),
                  ],
                ),
              if (wide) const VerticalDivider(width: 1),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}
