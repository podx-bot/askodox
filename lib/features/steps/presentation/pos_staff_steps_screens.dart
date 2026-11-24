import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../pos/data/pos_repository.dart';
import '../../pos/domain/pos_staff_tools.dart';
import '../../pos/presentation/my_payment_alerts_screen.dart' show askodoxStaffRoleLabel;
import '../../pos/presentation/pos_common.dart';
import 'step_kit.dart';

const _roles = ['manager', 'cashier', 'waiter', 'kitchen', 'accountant', 'attendant', 'delivery'];

/// Owner 2026-11-24 (3-step design, batch 14): the shop's people `/pos/:id/staff`. Top = how many people accept orders,
/// middle = ONE list (tap = pause / change role / remove), bottom = ONE big button (add a person: number + name -> role ->
/// done). What each person may open (ticks) stays on the old page in the menu ⋮.
class AskodoxPosStaffStepsScreen extends ConsumerStatefulWidget {
  const AskodoxPosStaffStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxPosStaffStepsScreen> createState() => _StaffState();
}

class _StaffState extends ConsumerState<AskodoxPosStaffStepsScreen> {
  List<AskodoxJson>? _members;
  Object? _error;
  int _step = 0; // 0 = the list, 1 = who, 2 = role, 3 = done
  final _phone = TextEditingController();
  final _name = TextEditingController();
  String _role = 'waiter';
  bool _busy = false;

  bool get _te => askodoxPosTe(context);
  AskodoxPosRepository get _repo => ref.read(askodoxPosRepositoryProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rows = await _repo.members(widget.businessId);
      if (mounted) {
        setState(() {
          _members = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && _members == null) setState(() => _error = e);
    }
  }

  Future<bool> _do(Future<Object?> Function() action) async {
    try {
      await action();
      await _load();
      return true;
    } on AskodoxPosException catch (e) {
      if (mounted) askodoxPosSnack(context, e.message(_te));
      return false;
    }
  }

  String _nameOf(AskodoxJson m) => '${m['label'] ?? ''}'.isNotEmpty ? '${m['label']}' : (m['role'] == 'owner' ? (_te ? 'మీరు' : 'You') : '••${m['phone_last4']}');

  Future<void> _person(AskodoxJson m) async {
    if (m['role'] == 'owner') return;
    final te = _te;
    final last4 = '${m['phone_last4']}';
    final active = m['active'] == true;
    final paused = m['paused'] == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_nameOf(m), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text('${askodoxStaffRoleLabel('${m['role']}', te)} · ••••$last4', style: const TextStyle(color: askodoxStepMuted)),
            const SizedBox(height: 12),
            if (!active)
              FilledButton(
                  key: Key('askodoxPosStaffStepsRestore-$last4'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                  onPressed: () => Navigator.pop(ctx, 'restore'),
                  child: Text(te ? 'తిరిగి తెచ్చు' : 'Bring back'))
            else ...[
              FilledButton(
                  key: Key('askodoxPosStaffStepsPause-$last4'),
                  style: FilledButton.styleFrom(backgroundColor: askodoxStepWarn, minimumSize: const Size.fromHeight(54)),
                  onPressed: () => Navigator.pop(ctx, 'pause'),
                  child: Text(paused ? (te ? 'మళ్లీ మొదలుపెట్టు' : 'Resume') : (te ? 'ఆపు (ఆర్డర్లు రావు)' : 'Pause (no orders reach them)'))),
              const SizedBox(height: 10),
              FilledButton(
                  key: Key('askodoxPosStaffStepsAccepts-$last4'),
                  style: FilledButton.styleFrom(backgroundColor: askodoxStepGreen, minimumSize: const Size.fromHeight(54)),
                  onPressed: () => Navigator.pop(ctx, 'accepts'),
                  child: Text(m['accepts_orders'] == true ? (te ? 'ఆర్డర్లు ఒప్పుకోవద్దు' : 'Stop accepting orders') : (te ? 'ఆర్డర్లు ఒప్పుకోవచ్చు' : 'May accept orders'))),
              const SizedBox(height: 10),
              Text(te ? 'పాత్ర మార్చు' : 'Change role', style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final r in _roles)
                  ChoiceChip(
                    key: Key('askodoxPosStaffStepsRole-$last4-$r'),
                    label: Text(askodoxStaffRoleLabel(r, te)),
                    selected: '${m['role']}' == r,
                    onSelected: (_) => Navigator.pop(ctx, 'role:$r'),
                  ),
              ]),
              const SizedBox(height: 14),
              OutlinedButton(
                  key: Key('askodoxPosStaffStepsRemove-$last4'),
                  style: OutlinedButton.styleFrom(foregroundColor: askodoxStepBad, minimumSize: const Size.fromHeight(50)),
                  onPressed: () => Navigator.pop(ctx, 'remove'),
                  child: Text(te ? 'తీసేయి' : 'Remove')),
            ],
          ]),
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'pause') {
      await _do(() => _repo.editMember(widget.businessId, last4, paused: !paused));
    } else if (action == 'accepts') {
      await _do(() => _repo.editMember(widget.businessId, last4, acceptsOrders: m['accepts_orders'] != true));
    } else if (action == 'restore') {
      await _do(() => _repo.editMember(widget.businessId, last4, role: '${m['role']}'));
    } else if (action.startsWith('role:')) {
      await _do(() => _repo.editMember(widget.businessId, last4, role: action.substring(5)));
    } else if (action == 'remove') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(te ? '${_nameOf(m)} ని తీసేయాలా?' : 'Remove ${_nameOf(m)}?'),
          content: Text(te ? 'ఈ షాప్ వాళ్లకి కనపడదు. పాత బిల్లుల్లో పేరు అలాగే ఉంటుంది. తర్వాత తిరిగి తేవచ్చు.' : 'They lose this shop. Old bills keep the name. You can bring them back.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(te ? 'వద్దు' : 'Cancel')),
            FilledButton(key: const Key('askodoxPosStaffStepsRemoveYes'), onPressed: () => Navigator.pop(ctx, true), child: Text(te ? 'తీసేయి' : 'Remove')),
          ],
        ),
      );
      if (ok == true) await _do(() => _repo.removeMember(widget.businessId, last4));
    }
  }

  Future<void> _save() async {
    final te = _te;
    final digits = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 10) {
      askodoxPosSnack(context, te ? '10 అంకెల నంబర్ రాయండి.' : 'Enter a 10 digit number.');
      setState(() => _step = 1);
      return;
    }
    setState(() => _busy = true);
    final ok = await _do(() => _repo.setMember(widget.businessId, digits.substring(digits.length - 10), _role,
        label: _name.text.trim(), acceptsOrders: true, tools: askodoxStaffStartTools(_role)));
    if (mounted) {
      setState(() {
        _busy = false;
        if (ok) _step = 3;
      });
    }
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    return [
      AskodoxStepMore('askodoxPosStaffStepsAlerts', te ? 'ఆర్డర్ అలర్ట్స్: ఏ స్టెప్ ఎవరికి' : 'Order alerts: who hears each step', Icons.notifications_active_rounded,
          () => context.push('/desk/${widget.businessId}/settings')),
      AskodoxStepMore('askodoxPosStaffStepsFull', te ? 'పాత పేజీ (ఏవి తెరవచ్చు)' : 'Old page (what they can open)', Icons.menu_book_rounded,
          () => context.push('/pos/${widget.businessId}/staff?full=1')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'సిబ్బంది' : 'Staff';
    if (_step == 1) {
      return AskodoxStepScaffold(
        key: const Key('askodoxPosStaffSteps1'),
        title: title,
        step: 1,
        total: 2,
        question: te ? 'ఎవరిని చేర్చాలి?' : 'Who do you add?',
        hint: te ? 'వాళ్లు అదే నంబర్‌తో ASKODOX లో సైన్ ఇన్ చేస్తే ఈ షాప్ కనిపిస్తుంది.' : 'They see this shop after signing in to ASKODOX with that number.',
        onBack: () => setState(() => _step = 0),
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          TextField(
              key: const Key('askodoxPosStaffStepsPhone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              maxLength: 13,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'ఫోన్ నంబర్ (10 అంకెలు)' : 'Phone number (10 digits)')),
          const SizedBox(height: 8),
          TextField(
              key: const Key('askodoxPosStaffStepsName'),
              controller: _name,
              maxLength: 40,
              decoration: InputDecoration(border: const OutlineInputBorder(), labelText: te ? 'పేరు' : 'Name')),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxPosStaffStepsNext1'),
          label: te ? 'తర్వాత' : 'Next',
          icon: Icons.arrow_forward_rounded,
          onPressed: _phone.text.replaceAll(RegExp(r'\D'), '').length < 10 ? null : () => setState(() => _step = 2),
        ),
      );
    }
    if (_step == 2) {
      return AskodoxStepScaffold(
        key: const Key('askodoxPosStaffSteps2'),
        title: title,
        step: 2,
        total: 2,
        question: te ? 'ఏ పని?' : 'Their job',
        onBack: () => setState(() => _step = 1),
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          for (final r in _roles)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AskodoxStepChoice(
                key: Key('askodoxPosStaffStepsPick-$r'),
                icon: Icons.badge_outlined,
                color: askodoxStepGreen,
                title: askodoxStaffRoleLabel(r, te),
                sub: '',
                selected: _role == r,
                onTap: () => setState(() => _role = r),
              ),
            ),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxPosStaffStepsSave'),
          label: te ? 'చేర్చు ✓' : 'Add ✓',
          icon: Icons.check_rounded,
          busy: _busy,
          onPressed: _busy ? null : _save,
        ),
      );
    }
    if (_step == 3) {
      return AskodoxStepScaffold(
        key: const Key('askodoxPosStaffSteps3'),
        title: title,
        step: 2,
        total: 2,
        more: _more(),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 28, 16, 16), children: [
          const Center(child: AskodoxStepDoneMark()),
          const SizedBox(height: 26),
          AskodoxStepBigNumber(_name.text.trim().isEmpty ? '••${_phone.text.replaceAll(RegExp(r'\D'), '').characters.takeLast(4)}' : _name.text.trim(),
              label: te ? 'చేరారు · ${askodoxStaffRoleLabel(_role, te)}' : 'Added · ${askodoxStaffRoleLabel(_role, te)}', size: 32),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(te ? 'వాళ్లు అదే నంబర్‌తో ASKODOX లో సైన్ ఇన్ చేయాలి.' : 'They sign in to ASKODOX with that number.', textAlign: TextAlign.center),
          ),
        ]),
        bottom: AskodoxStepBottom(
          buttonKey: const Key('askodoxPosStaffStepsDone'),
          label: te ? 'లిస్ట్‌కి' : 'Back to the list',
          icon: Icons.arrow_back_rounded,
          onPressed: () => setState(() {
            _step = 0;
            _phone.clear();
            _name.clear();
          }),
        ),
      );
    }
    final rows = _members;
    if (rows == null) {
      return AskodoxStepScaffold(
          key: const Key('askodoxPosStaffSteps'),
          title: title,
          more: _more(),
          body: _error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()));
    }
    final current = [for (final m in rows) if (m['active'] == true) m]..sort((a, b) => (a['role'] == 'owner' ? 0 : 1).compareTo(b['role'] == 'owner' ? 0 : 1));
    final removed = [for (final m in rows) if (m['active'] != true) m];
    final accepting = current.where((m) => m['role'] == 'owner' || (m['accepts_orders'] == true && m['paused'] != true)).length;
    // Short word on the right (the row has little room); the longer wording sits under the name.
    String status(AskodoxJson m) {
      if (m['role'] == 'owner') return te ? 'ఎప్పుడూ' : 'Always';
      if (m['active'] != true) return te ? 'తీసేశారు' : 'Removed';
      if (m['paused'] == true) return te ? 'ఆపారు' : 'Paused';
      return m['accepts_orders'] == true ? (te ? 'ఆన్' : 'On') : (te ? 'లేదు' : 'No');
    }

    return AskodoxStepScaffold(
      key: const Key('askodoxPosStaffSteps'),
      title: title,
      more: _more(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
          AskodoxStepBigNumber('$accepting', label: te ? 'మంది ఆర్డర్లు ఒప్పుకుంటారు' : 'people accept orders', size: 44),
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
                te ? 'కొత్త ఆర్డర్ వస్తే వీళ్ల ఫోన్లలో మోగుతుంది. ఎవరో ఒకరు నొక్కితే చాలు.' : 'A new order rings these phones; one tap from any is enough.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: askodoxStepMuted)),
          ),
          for (final m in [...current, ...removed])
            AskodoxStepPersonRow(
              key: Key('askodoxPosStaffStepsRow-${m['phone_last4']}'),
              name: _nameOf(m),
              sub: '${askodoxStaffRoleLabel('${m['role']}', te)} · ••${m['phone_last4']}',
              amount: status(m),
              amountColor: m['active'] != true || m['paused'] == true ? askodoxStepMuted : askodoxStepDone,
              onTap: () => _person(m),
            ),
        ]),
      ),
      bottom: AskodoxStepBottom(
        buttonKey: const Key('askodoxPosStaffStepsAdd'),
        label: te ? 'వ్యక్తిని చేర్చు' : 'Add a person',
        icon: Icons.person_add_alt_1,
        onPressed: () => setState(() => _step = 1),
      ),
    );
  }
}
