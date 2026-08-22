import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../application/admin_controller.dart';
import '../domain/admin_models.dart';

class AdminLoginScreen extends ConsumerStatefulWidget { const AdminLoginScreen({super.key}); @override ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState(); }
class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  AdminRole role = AdminRole.superAdmin;
  @override Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Card(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [Icon(Icons.admin_panel_settings, size: 54, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16), Text('PODX Admin', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center), const Text('Mock secure access • local data only', textAlign: TextAlign.center), const SizedBox(height: 24), DropdownButtonFormField<AdminRole>(isExpanded: true, initialValue: role, decoration: const InputDecoration(labelText: 'Admin role', border: OutlineInputBorder()), items: [for (final value in AdminRole.values) DropdownMenuItem(value: value, child: Text(value.label, overflow: TextOverflow.ellipsis))], onChanged: (value) { if (value != null) setState(() => role = value); }), const SizedBox(height: 16), FilledButton.icon(onPressed: () async { await ref.read(adminControllerProvider.notifier).login(role); if (context.mounted) context.go('/admin/dashboard'); }, icon: const Icon(Icons.login), label: const Text('Sign in'))]))))));
}

class AdminShell extends ConsumerWidget {
  const AdminShell({required this.child, super.key}); final Widget child;
  @override Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(adminControllerProvider).user;
    if (user == null) return const AdminLoginScreen();
    final allowed = sectionsFor(user.role).toList();
    final location = GoRouterState.of(context).uri.pathSegments.last;
    return Scaffold(appBar: AppBar(title: Text('PODX Admin · ${user.role.label}'), actions: [IconButton(onPressed: () => ref.read(adminControllerProvider.notifier).logout(), icon: const Icon(Icons.logout))]), body: Row(children: [NavigationRail(selectedIndex: allowed.indexWhere((e) => e.name == location).clamp(0, allowed.length - 1), onDestinationSelected: (i) => context.go('/admin/${allowed[i].name}'), destinations: [for (final section in allowed) NavigationRailDestination(icon: Icon(section.icon), label: Text(section.label))]), const VerticalDivider(width: 1), Expanded(child: child)]));
  }
}
