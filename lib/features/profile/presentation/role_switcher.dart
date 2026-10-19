import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/backend_providers.dart';
import '../../home/domain/active_role.dart';
import '../data/user_profile_repository.dart';

/// Which Profile sections belong to the ACTIVE role. One shared profile; the
/// role only decides what is shown -- nothing is created or opened.
bool askodoxRoleShowsBusiness(AskodoxUserRole role) =>
    role == AskodoxUserRole.seller ||
    role == AskodoxUserRole.serviceProvider ||
    role == AskodoxUserRole.farmer ||
    role == AskodoxUserRole.distributor;

bool askodoxRoleShowsStudio(AskodoxUserRole role) =>
    askodoxRoleShowsBusiness(role) || role == AskodoxUserRole.influencer;

bool askodoxRoleShowsOpportunities(AskodoxUserRole role) =>
    askodoxRoleShowsBusiness(role) || role == AskodoxUserRole.jobSeeker;

bool askodoxRoleShowsPartner(AskodoxUserRole role) =>
    role == AskodoxUserRole.deliveryPartner || role == AskodoxUserRole.driver;

/// Compact role switcher: one row of the roles the person holds. Tapping a
/// role only switches the ACTIVE role (saved + announced) -- it never creates
/// a listing and never navigates. Held roles are edited in a small sheet.
class AskodoxRoleSwitcher extends ConsumerWidget {
  const AskodoxRoleSwitcher({super.key, required this.telugu});

  final bool telugu;

  String _t(String en, String te) => telugu ? te : en;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(askodoxRoleProvider);
    final shown = [
      for (final r in AskodoxUserRole.values)
        if (roles.owned.contains(r) || r == roles.active) r,
    ];
    return Padding(
      key: const Key('askodoxRoleSwitcher'),
      padding: const EdgeInsets.only(top: 6),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final role in shown)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    key: ValueKey('askodoxRoleSwitch-${role.name}'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    selected: role == roles.active,
                    label: Text(askodoxUserRoleLabel(role, telugu: telugu), style: const TextStyle(fontSize: 12.5)),
                    onSelected: (_) => _switch(context, ref, roles.active, role),
                  ),
                ),
            ]),
          ),
        ),
        IconButton(
          key: const Key('askodoxEditRoles'),
          tooltip: _t('My roles', 'నా పాత్రలు'),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.tune_rounded, size: 20),
          onPressed: () => _editHeld(context),
        ),
      ]),
    );
  }

  void _switch(BuildContext context, WidgetRef ref, AskodoxUserRole from, AskodoxUserRole to) {
    if (from == to) return;
    ref.read(askodoxRoleProvider.notifier).setActive(to);
    if (ref.read(authSessionProvider).user != null) {
      ref.read(askodoxUserProfileProvider.notifier).save({'active_role': to.name});
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const Key('askodoxActiveRoleChanged'),
        content: Text(askodoxRoleChangedMessage(from, to, telugu: telugu)),
      ));
  }

  Future<void> _editHeld(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Consumer(builder: (context, ref, _) {
              final roles = ref.watch(askodoxRoleProvider);
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_t('Roles you hold', 'మీ పాత్రలు'),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                    _t('One profile for all of them. Adding a role creates nothing by itself.',
                        'అన్నింటికీ ఒకే ప్రొఫైల్. పాత్ర జోడిస్తే ఏదీ తనంతట తాను తయారవదు.'),
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085))),
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  for (final role in {...askodoxProfileRoles, roles.active})
                    FilterChip(
                      key: ValueKey('profileRole-${role.name}'),
                      visualDensity: VisualDensity.compact,
                      selected: roles.owned.contains(role),
                      side: role == roles.active ? const BorderSide(color: Color(0xFF1769FF), width: 2) : null,
                      label: Text(role == roles.active
                          ? '${askodoxUserRoleLabel(role, telugu: telugu)} · ${_t('Active now', 'ఇప్పుడు యాక్టివ్')}'
                          : askodoxUserRoleLabel(role, telugu: telugu)),
                      onSelected: (value) {
                        ref.read(askodoxRoleProvider.notifier).toggleOwned(role, value);
                        if (ref.read(authSessionProvider).user != null) {
                          final held = ref.read(askodoxRoleProvider).owned.map((r) => r.name).toList()..sort();
                          ref.read(askodoxUserProfileProvider.notifier).save({'roles': held});
                        }
                      },
                    ),
                ]),
              ]);
            }),
          ),
        ),
      );
}
