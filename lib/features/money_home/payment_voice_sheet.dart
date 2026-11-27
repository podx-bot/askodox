import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/backend_providers.dart';
import '../business/presentation/biz_hub.dart' show askodoxBizRoute;
import '../pos/data/pos_payment_alerts.dart';

/// One kind of money message the phone can say (owner 2026-11-22: "bill paid / loan instalment" too, plus refunds,
/// cashback, cancelled, generated, autopay -- and a fake message is never read as money, the phone warns instead).
class AskodoxVoiceKind {
  const AskodoxVoiceKind(this.id, this.en, this.te, this.sampleEn, this.sampleTe, {this.locked = false});
  final String id;
  final String en, te;

  /// What the phone says (example words).
  final String sampleEn, sampleTe;

  /// Always on (the fake-message warning).
  final bool locked;

  String label(bool te) => te ? this.te : en;
  String sample(bool te) => te ? sampleTe : sampleEn;
}

const _in = AskodoxVoiceKind('in', 'Money received', 'డబ్బు వచ్చింది', '"200 rupees received from Ramesh"',
    '"రమేష్ నుంచి 200 రూపాయలు అందింది"');
const _out = AskodoxVoiceKind('out', 'Money sent', 'డబ్బు పంపారు', '"500 rupees sent to Suresh"', '"సురేష్‌కి 500 రూపాయలు పంపారు"');
const _bill = AskodoxVoiceKind('bill', 'Bill / EMI paid', 'బిల్లు / EMI కట్టారు', '"Bajaj Finance loan instalment of 4133 rupees paid"',
    '"Bajaj Finance లోన్ వాయిదా 4133 రూపాయలు కట్టారు"');
const _refund = AskodoxVoiceKind('refund', 'Refund came', 'రీఫండ్ వచ్చింది', '"Refund of 499 rupees came"', '"499 రూపాయలు రీఫండ్ వచ్చింది"');
const _cashback = AskodoxVoiceKind('cashback', 'Cashback / interest', 'క్యాష్‌బ్యాక్ / వడ్డీ', '"Cashback of 50 rupees came"',
    '"50 రూపాయలు క్యాష్‌బ్యాక్ వచ్చింది"');
const _pending = AskodoxVoiceKind('pending', 'Pending / processing', 'పెండింగ్ / ప్రాసెస్', '"Refund of 499 started -- not here yet"',
    '"499 రూపాయల రీఫండ్ మొదలైంది — ఇంకా రాలేదు"');
const _failed = AskodoxVoiceKind('failed', 'Failed / cancelled', 'ఫెయిల్ / క్యాన్సిల్', '"Payment of 300 rupees failed"',
    '"300 రూపాయల పేమెంట్ ఫెయిల్ అయింది"');
const _due = AskodoxVoiceKind('due', 'Bill generated / due', 'బిల్లు వచ్చింది / కట్టాలి', '"Electricity bill of 962 rupees -- to be paid"',
    '"కరెంట్ బిల్లు 962 రూపాయలు — కట్టాలి"');
const _autopay = AskodoxVoiceKind('autopay', 'Autopay set / stopped', 'ఆటోపే', '"Autopay of 499 rupees set for Netflix"',
    '"Netflix కి 499 రూపాయల ఆటోపే పెట్టారు"');
const _request = AskodoxVoiceKind('request', 'Money asked (collect)', 'డబ్బు అడిగారు', '"Someone asked for 2000 rupees -- check before you pay"',
    '"ఎవరో 2000 రూపాయలు అడిగారు — చూసి కట్టండి"');
const _fake = AskodoxVoiceKind('fake', 'Looks fake (warning)', 'ఫేక్‌లా ఉంది (హెచ్చరిక)', '"Careful -- this message looks fake. Not counted."',
    '"జాగ్రత్త — ఈ మెసేజ్ ఫేక్‌లా ఉంది. లెక్కలో వేయలేదు."',
    locked: true);

/// The person's own phone: every kind. A shop phone only says money that came in, refunds, collect requests and the
/// fake warning (a shop's own debits are the owner's business, not the counter's).
const askodoxPersonalVoiceKinds = [_in, _out, _bill, _refund, _cashback, _pending, _failed, _due, _autopay, _request, _fake];
const askodoxShopVoiceKinds = [_in, _refund, _request, _fake];

/// Pilot finding 2026-11-26: fifteen lines on one sheet was too many for a first look. These four are shown first (every
/// kind stays reachable under "More"); a list of four or fewer (a shop counter) is shown whole.
const askodoxPrimaryVoiceIds = {'in', 'out', 'request', 'fake'};

/// ASKODOX lines (owner 2026-11-23, all ON by default; each can be switched off): the ASKODOX tune before every voice,
/// a hello before the day's first payment, the night count (only on a day with payments -- no payment = nothing) and a
/// short line for customers (at most twice a day). ASKODOX is named as the voice, never as where the money went.
const _tune = AskodoxVoiceKind('tune', 'ASKODOX tune', 'ASKODOX ట్యూన్', 'A short ASKODOX tune before every payment voice',
    'ప్రతి పేమెంట్ వాయిస్ ముందు చిన్న ASKODOX ట్యూన్');
const _hello = AskodoxVoiceKind('hello', 'Morning hello', 'ఉదయం నమస్తే',
    '"Hello! ASKODOX will tell you today\'s payments." -- before the day\'s first payment',
    '"నమస్తే! ఈరోజు మీ పేమెంట్స్ ASKODOX చెప్తుంది." — రోజు మొదటి పేమెంట్ ముందు');
const _night = AskodoxVoiceKind('night', 'Night ASKODOX count', 'రాత్రి ASKODOX లెక్క',
    '"ASKODOX count: 45 payments came today, total 12400 rupees." -- 9 pm, only on a day with payments',
    '"ASKODOX లెక్క: ఈరోజు 45 పేమెంట్స్ వచ్చాయి, మొత్తం 12400 రూపాయలు." — రాత్రి 9కి, పేమెంట్ వచ్చిన రోజే');
const _customer = AskodoxVoiceKind('customer', 'ASKODOX line for customers', 'Customers కి ASKODOX మాట',
    '"This voice is from ASKODOX. Free for you too." -- at most twice a day',
    '"ఈ సౌండ్ ASKODOX ది. మీకు కూడా ఫ్రీ." — రోజుకు 2 సార్లు మాత్రమే');

/// The ASKODOX lines, the same on my phone and on a shop counter.
const askodoxBrandVoiceKinds = [_tune, _hello, _night, _customer];

/// On / off for each kind: a saved choice wins; otherwise everything is on except "out", which follows the older
/// "say money sent" switch. The fake warning is always on (same rule as the phone's native `voiceOn`).
Map<String, bool> askodoxVoiceKindsWithDefaults(Map<String, bool> saved, List<AskodoxVoiceKind> kinds, {bool announceDebits = false}) => {
      for (final k in kinds) k.id: k.locked ? true : (saved[k.id] ?? (k.id == 'out' ? announceDebits : true)),
    };

/// The Payment voice folder: what this phone says out loud, one line per kind (✓ on / − off), the words it says and ▶ to
/// hear them. [businessId] null = the person's own phone (Buyer side); a shop id = that shop's counter sound.
Future<void> askodoxOpenPaymentVoice(BuildContext context, {String? businessId}) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => AskodoxPaymentVoiceSheet(businessId: businessId),
    );

class AskodoxPaymentVoiceSheet extends ConsumerStatefulWidget {
  const AskodoxPaymentVoiceSheet({super.key, this.businessId, this.inSheet = true});
  final String? businessId;

  /// False when shown as its own page (`/payment-voice`, e.g. from a Home chat shortcut).
  final bool inSheet;

  @override
  ConsumerState<AskodoxPaymentVoiceSheet> createState() => _AskodoxPaymentVoiceSheetState();
}

class _AskodoxPaymentVoiceSheetState extends ConsumerState<AskodoxPaymentVoiceSheet> {
  bool get _personal => widget.businessId == null;
  List<AskodoxVoiceKind> get _kinds => _personal ? askodoxPersonalVoiceKinds : askodoxShopVoiceKinds;

  List<AskodoxVoiceKind> get _primaryKinds =>
      _kinds.length <= 4 ? _kinds : [for (final k in _kinds) if (askodoxPrimaryVoiceIds.contains(k.id)) k];
  List<AskodoxVoiceKind> get _moreKinds => [for (final k in _kinds) if (!_primaryKinds.contains(k)) k];

  /// Money kinds + the ASKODOX lines: one on / off map, saved together.
  List<AskodoxVoiceKind> get _allKinds => [..._kinds, ...askodoxBrandVoiceKinds];
  Map<String, bool>? _on;
  AskodoxMyPhoneAlerts? _mine;
  String? _playing;

  /// Pilot finding 2026-11-26: the phone could not read / keep the choice -> say so, never show defaults as saved.
  bool _loadFailed = false;

  /// "More" (the less used kinds + the ASKODOX lines) is folded until asked for: four lines first, not fifteen.
  bool _showMore = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final bridge = ref.read(askodoxPaymentAlertsBridgeProvider);
    var saved = <String, bool>{};
    var failed = false;
    try {
      final read = await bridge.readVoiceKinds(personal: _personal);
      if (read == null) {
        failed = true;
      } else {
        saved = read;
      }
    } catch (_) {
      failed = true;
    }
    AskodoxMyPhoneAlerts? mine;
    if (_personal) {
      try {
        mine = await AskodoxMyPhoneAlerts.load();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _mine = mine;
      _loadFailed = failed;
      _on = askodoxVoiceKindsWithDefaults(saved, _allKinds, announceDebits: mine?.announceDebits ?? false);
    });
  }

  Future<void> _toggle(AskodoxVoiceKind kind) async {
    final on = _on;
    if (on == null || kind.locked) return;
    final next = {...on, kind.id: !(on[kind.id] ?? true)};
    setState(() => _on = next);
    final bridge = ref.read(askodoxPaymentAlertsBridgeProvider);
    var kept = false;
    try {
      kept = await bridge.saveVoiceKinds({for (final e in next.entries) if (e.key != 'fake') e.key: e.value}, personal: _personal);
    } catch (_) {}
    if (!kept) {
      // Not kept by the phone: put the switch back and say so (it used to stay changed while the phone kept the old choice).
      if (!mounted) return;
      setState(() => _on = on);
      final te = Localizations.localeOf(context).languageCode == 'te';
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        key: const Key('askodoxVoiceSaveFailed'),
        content: Text(te ? 'సేవ్ కాలేదు, మళ్ళీ ప్రయత్నించండి' : 'Not saved - please try again'),
      ));
      return;
    }
    // "Money sent" is also the older switch on My phone payments: keep both the same.
    final mine = _mine;
    if (kind.id == 'out' && mine != null) {
      mine.announceDebits = next['out'] ?? false;
      await mine.save();
      try {
        final base = ref.read(appConfigProvider).apiBaseUrl?.toString() ?? '';
        final session = ref.read(authSessionProvider);
        final token = session.user == null ? '' : (session.tokenPlaceholder ?? '');
        await bridge.configurePersonal(mine.nativeConfig(baseUrl: base, token: token));
      } catch (_) {}
    }
  }

  Future<void> _play(AskodoxVoiceKind kind, String language) async {
    setState(() => _playing = kind.id);
    try {
      await ref.read(askodoxPaymentAlertsBridgeProvider).speakKind(kind.id, personal: _personal, language: language);
    } catch (_) {}
    if (mounted) setState(() => _playing = null);
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final language = _mine?.language ?? Localizations.localeOf(context).languageCode;
    final on = _on;
    final count = on == null ? 0 : _kinds.where((k) => on[k.id] ?? true).length;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .86),
        child: ListView(
          key: const Key('askodoxPaymentVoiceSheet'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: const Color(0xFF0D9488), borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.volume_up_rounded, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(te ? 'పేమెంట్ వాయిస్' : 'Payment voice', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                  Text(
                      on == null
                          ? (te ? 'చదువుతోంది…' : 'Loading…')
                          : te
                              ? '${_kinds.length} లో $count ఆన్ · ${_personal ? 'నా ఫోన్' : 'షాప్ కౌంటర్'}'
                              : '$count of ${_kinds.length} on · ${_personal ? 'my phone' : 'shop counter'}',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
                ]),
              ),
            ]),
            const SizedBox(height: 10),
            Text(
                te
                    ? 'ఏది వచ్చినప్పుడు ఫోన్ చెప్పాలో నొక్కి ఆన్ / ఆఫ్ చేయండి. ▶ నొక్కితే ఎలా చెబుతుందో వినిపిస్తుంది. ఫేక్ మెసేజ్ హెచ్చరిక ఎప్పుడూ ఆన్.'
                    : 'Tap a line to switch it on / off. ▶ plays the words. The fake-message warning is always on.',
                style: const TextStyle(fontSize: 12.5, color: Color(0xFF5B6475))),
            const SizedBox(height: 10),
            if (_loadFailed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    te
                        ? 'ఫోన్ లో సేవ్ చేసినది చదవలేకపోయాను. ఇక్కడ చూపేవి మామూలు సెట్టింగ్స్ మాత్రమే.'
                        : "Couldn't read what this phone saved. These are the usual settings only.",
                    key: const Key('askodoxVoiceLoadFailed'),
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFB45309), fontWeight: FontWeight.w700)),
              ),
            if (on == null)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else ...[
              for (final k in _primaryKinds) _row(k, on[k.id] ?? true, te, language),
              if (_moreKinds.isNotEmpty || askodoxBrandVoiceKinds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton.icon(
                    key: const Key('askodoxVoiceMoreKinds'),
                    onPressed: () => setState(() => _showMore = !_showMore),
                    icon: Icon(_showMore ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                    label: Text(_showMore
                        ? (te ? 'తక్కువ చూపు' : 'Show less')
                        : (te ? 'ఇంకా (${_moreKinds.length + askodoxBrandVoiceKinds.length})' : 'More (${_moreKinds.length + askodoxBrandVoiceKinds.length})')),
                  ),
                ),
              if (_showMore) ...[
                for (final k in _moreKinds) _row(k, on[k.id] ?? true, te, language),
                const SizedBox(height: 6),
                Text(te ? 'ASKODOX మాటలు' : 'ASKODOX lines',
                    key: const Key('askodoxPaymentVoiceBrand'), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                const SizedBox(height: 2),
                Text(
                    te
                        ? 'అన్నీ ఆన్. పేమెంట్ రాని రోజు ఏ మాటా రాదు. ఏదైనా వద్దంటే నొక్కి ఆపండి.'
                        : 'All on. On a day with no payment nothing is said. Tap one to switch it off.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF5B6475))),
                const SizedBox(height: 8),
                for (final k in askodoxBrandVoiceKinds) _row(k, on[k.id] ?? true, te, language),
              ],
            ],
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('askodoxPaymentVoiceMore'),
              onPressed: () {
                if (widget.inSheet) Navigator.of(context).pop();
                final id = widget.businessId;
                context.push(id == null ? '/me/payments/phone?open=voice' : askodoxBizRoute(id, 'money.sound'));
              },
              icon: const Icon(Icons.tune_rounded),
              label: Text(_personal
                  ? (te ? 'భాష, పేరు, ఖాతా పేరు చెప్పాలా' : 'Language, say names, account names')
                  : (te ? 'సిబ్బంది ఫోన్లు, ఎవరికి ఏ సౌండ్' : 'Staff phones, who hears what')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(AskodoxVoiceKind k, bool active, bool te, String language) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: active ? const Color(0xFFEFFBF7) : const Color(0xFFF4F5F7),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: ValueKey('askodoxVoiceKind-${k.id}'),
            borderRadius: BorderRadius.circular(14),
            onTap: k.locked ? null : () => _toggle(k),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
              child: Row(children: [
                Semantics(
                  toggled: active,
                  label: k.label(te),
                  child: Switch(
                    key: ValueKey('askodoxVoiceKindDot-${k.id}-${active ? 'on' : 'off'}'),
                    value: active,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    thumbColor: WidgetStatePropertyAll(Theme.of(context).colorScheme.surface),
                    activeTrackColor: k.locked ? const Color(0xFFB45309) : const Color(0xFF12A150),
                    inactiveTrackColor: const Color(0xFFC5CAD3),
                    onChanged: k.locked ? null : (_) => _toggle(k),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k.label(te), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    if (k.locked)
                      Text(te ? 'ఎప్పుడూ ఆన్ (మార్చలేరు)' : 'Always on (cannot be changed)',
                          key: ValueKey('askodoxVoiceKindLocked-${k.id}'),
                          style: const TextStyle(fontSize: 11.5, color: Color(0xFFB45309), fontWeight: FontWeight.w800)),
                    Text(k.sample(te),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: active ? const Color(0xFF1F5F4F) : const Color(0xFF7A8190))),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(active ? (te ? 'ఆన్' : 'ON') : (te ? 'ఆఫ్' : 'OFF'),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: active ? const Color(0xFF12A150) : const Color(0xFF7A8190))),
                IconButton(
                  key: ValueKey('askodoxVoiceKindPlay-${k.id}'),
                  tooltip: te ? 'వినండి' : 'Listen',
                  onPressed: _playing == null ? () => _play(k, language) : null,
                  icon: _playing == k.id
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_circle_fill_rounded, color: Color(0xFF0D9488)),
                ),
              ]),
            ),
          ),
        ),
      );
}
