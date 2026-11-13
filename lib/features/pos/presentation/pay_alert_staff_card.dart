import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/pos_repository.dart';
import 'my_payment_alerts_screen.dart' show askodoxPaymentAlertStaffRoles, askodoxStaffRoleLabel;
import 'pos_common.dart';

/// The owner's staff for payment alerts (redesign 2026-11-13: ONE place, inside the shop's alert
/// page under "who hears it" -- it used to sit on the shop list page as well). Staff are added by
/// mobile number + role + an optional spoken name; only the last four digits are ever shown.
class AskodoxPayAlertStaffCard extends ConsumerStatefulWidget {
  const AskodoxPayAlertStaffCard({super.key, required this.businessId, this.onChanged});

  final String businessId;

  /// Called after a person is added (the page reloads who can hear).
  final VoidCallback? onChanged;

  @override
  ConsumerState<AskodoxPayAlertStaffCard> createState() => _AskodoxPayAlertStaffCardState();
}

class _AskodoxPayAlertStaffCardState extends ConsumerState<AskodoxPayAlertStaffCard> {
  List<AskodoxJson>? _members;
  String? _message;
  bool _busy = false;
  final _phone = TextEditingController();
  final _label = TextEditingController();
  String _role = 'cashier';

  String get _id => widget.businessId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phone.dispose();
    _label.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final members = await ref.read(askodoxPosRepositoryProvider).members(_id);
      if (mounted) setState(() => _members = members);
    } on AskodoxPosException {
      if (mounted) setState(() => _members = const []);
    }
  }

  Future<void> _add(bool te) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(askodoxPosRepositoryProvider).setMember(_id, _phone.text.trim(), _role, label: _label.text);
      _phone.clear();
      _label.clear();
      await _load();
      widget.onChanged?.call();
      if (mounted) {
        setState(() => _message = te
            ? 'జోడించాం. వాళ్ళు తమ ఫోన్‌లో ASKODOX తెరిచి పేమెంట్లు → అలర్ట్స్ లో సౌండ్ ఆన్ చేసుకోవాలి.'
            : 'Added. They open ASKODOX on their phone and switch the sound on in Payments → Alerts.');
      }
    } on AskodoxPosException catch (e) {
      if (mounted) setState(() => _message = e.message(te));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final te = askodoxPosTe(context);
    final staff = (_members ?? const <AskodoxJson>[]).where((m) => m['active'] == true && '${m['role']}' != 'owner').toList();
    return Card(
      key: const Key('askodoxPayAlertStaff'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(te ? 'సిబ్బంది' : 'Staff', style: const TextStyle(fontWeight: FontWeight.w800)),
          if (_members == null)
            const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()))
          else if (staff.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(te ? 'ఇంకా ఎవరినీ జోడించలేదు.' : 'Nobody added yet.', style: const TextStyle(fontSize: 12.5)),
            ),
          for (final m in staff)
            ListTile(
              key: ValueKey('askodoxMyPaymentAlertsStaff-$_id-${m['phone_last4']}'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline_rounded),
              title: Text('${m['label'] ?? ''}'.isEmpty ? '••••••${m['phone_last4']}' : '${m['label']} · ••••••${m['phone_last4']}'),
              subtitle: Text(askodoxStaffRoleLabel('${m['role']}', te)),
            ),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('askodoxMyPaymentAlertsLabel-$_id'),
            controller: _label,
            maxLength: 40,
            decoration: InputDecoration(
                counterText: '',
                labelText: te ? 'పేరు (మీకు నచ్చినది, ఉదా. భార్య / స్టాఫ్ 1)' : 'Name (any, e.g. Wife / Staff 1)',
                helperText: te ? 'పేమెంట్ వచ్చినప్పుడు ఈ పేరు చెబుతుంది.' : 'This name is spoken with their payments.'),
          ),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              flex: 3,
              child: TextField(
                key: ValueKey('askodoxMyPaymentAlertsPhone-$_id'),
                controller: _phone,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(counterText: '', labelText: te ? 'మొబైల్ నంబర్' : 'Mobile number'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                key: ValueKey('askodoxMyPaymentAlertsRole-$_id'),
                isExpanded: true,
                initialValue: _role,
                items: [
                  for (final r in askodoxPaymentAlertStaffRoles) DropdownMenuItem(value: r, child: Text(askodoxStaffRoleLabel(r, te))),
                ],
                onChanged: (v) => setState(() => _role = v ?? 'cashier'),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            key: ValueKey('askodoxMyPaymentAlertsAdd-$_id'),
            onPressed: _busy || _phone.text.trim().length != 10 ? null : () => _add(te),
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: Text(te ? 'సిబ్బందిని జోడించు' : 'Add staff'),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_message!, key: const Key('askodoxMyPaymentAlertsMessage'), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ]),
      ),
    );
  }
}
