import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/widgets/qr_poster.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_common.dart';
import '../domain/shop_link_logic.dart';
import 'step_kit.dart';

/// `/pos/:id/link` (owner 2026-11-22, design artifact GyGuSkNsVrf6cxXQBZk7h4): the shop's ONE free public page,
/// `askodox.com/s/<name>`, in 3 steps -- ① what to show (menu + prices, call, map, own UPI, an offer line, the WhatsApp
/// number orders go to) ② colour + link name (checked live) ③ ✓ the link: WhatsApp / copy / QR poster / open, and how
/// many people saw it. Only the OWNER makes or changes it; a manager sees step 3. A made link opens on step 3.
class AskodoxShopLinkStepsScreen extends ConsumerStatefulWidget {
  const AskodoxShopLinkStepsScreen({super.key, required this.businessId});
  final String businessId;

  @override
  ConsumerState<AskodoxShopLinkStepsScreen> createState() => _AskodoxShopLinkStepsScreenState();
}

class _AskodoxShopLinkStepsScreenState extends ConsumerState<AskodoxShopLinkStepsScreen> {
  final _slug = TextEditingController();
  final _offer = TextEditingController();
  final _whatsapp = TextEditingController();
  AskodoxJson? _data;
  Object? _error;
  int _step = 1;
  bool _busy = false;
  String _color = 'green';
  final Map<String, bool> _show = {'show_menu': true, 'show_prices': true, 'show_call': true, 'show_map': true, 'show_pay': true};
  String _slugProblem = '';
  Timer? _checkTimer;
  int _checkSeq = 0;

  bool get _te => askodoxPosTe(context);
  AskodoxJson get _link => askodoxPosMap(_data?['link']);
  bool get _made => _link.isNotEmpty;
  bool get _owner => _data?['can_change'] == true;
  String get _shop => '${askodoxPosMap(_data?['shop'])['name'] ?? ''}';
  String get _url => '${_link['url'] ?? ''}';
  Color get _tone => Color(askodoxShopLinkColors[_color] ?? askodoxShopLinkColors['green']!);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _slug.dispose();
    _offer.dispose();
    _whatsapp.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await ref.read(askodoxPosRepositoryProvider).shopLink(widget.businessId);
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _fill();
        if (_made || d['can_change'] != true) _step = 3;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Boxes from the saved link (or the defaults + the suggested name + the shop phone).
  void _fill() {
    final link = _link;
    _slug.text = '${link['slug'] ?? _data?['suggested_slug'] ?? ''}';
    _offer.text = '${link['offer'] ?? ''}';
    // The saved number, else the shop phone, else the owner's own sign-in number (the server says which).
    var saved = '${link['whatsapp'] ?? ''}';
    if (saved.isEmpty) saved = '${_data?['whatsapp_default'] ?? askodoxPosMap(_data?['shop'])['phone'] ?? ''}';
    final phone = saved.replaceAll(RegExp(r'\D'), '');
    _whatsapp.text = phone.length > 10 ? phone.substring(phone.length - 10) : phone;
    final color = '${link['color'] ?? ''}';
    if (askodoxShopLinkColors.containsKey(color)) _color = color;
    for (final key in _show.keys.toList()) {
      if (link[key] is bool) _show[key] = link[key] as bool;
    }
    _slugProblem = askodoxSlugProblem(_slug.text);
  }

  void _slugChanged(String raw) {
    final cleaned = askodoxCleanSlug(raw);
    if (cleaned != _slug.text) {
      _slug.value = TextEditingValue(text: cleaned, selection: TextSelection.collapsed(offset: cleaned.length));
    }
    setState(() => _slugProblem = askodoxSlugProblem(cleaned));
    _checkTimer?.cancel();
    if (_slugProblem.isNotEmpty || cleaned == '${_link['slug'] ?? ''}') return;
    final seq = ++_checkSeq;
    _checkTimer = Timer(const Duration(milliseconds: 600), () async {
      try {
        final out = await ref.read(askodoxPosRepositoryProvider).checkShopLink(widget.businessId, cleaned);
        if (mounted && seq == _checkSeq) setState(() => _slugProblem = '${out['problem'] ?? ''}');
      } catch (_) {/* the save says it again */}
    });
  }

  Future<void> _save({bool? enabled}) async {
    final te = _te;
    final slug = askodoxCleanSlug(_slug.text);
    final problem = askodoxSlugProblem(slug);
    if (problem.isNotEmpty) {
      setState(() => _slugProblem = problem);
      askodoxPosSnack(context, askodoxSlugProblemText(problem, te)!);
      return;
    }
    setState(() => _busy = true);
    try {
      final out = await ref.read(askodoxPosRepositoryProvider).saveShopLink(widget.businessId, {
        'slug': slug,
        ..._show,
        'offer': _offer.text.trim(),
        'color': _color,
        'whatsapp': _whatsapp.text.trim(),
        if (enabled != null) 'enabled': enabled,
      });
      if (!mounted) return;
      setState(() {
        _data = {...?_data, 'link': out['link']};
        _step = 3;
      });
    } on AskodoxPosException catch (e) {
      if (!mounted) return;
      if (e.code.startsWith('slug_')) setState(() => _slugProblem = e.code == 'slug_taken' ? 'taken' : e.code.substring(5));
      final text = switch (e.code) {
        'slug_taken' => askodoxSlugProblemText('taken', te)!,
        'no_links' => te ? 'ఆఫర్ లైన్‌లో వెబ్ లింక్‌లు వద్దు.' : 'No web links in the offer line.',
        'whatsapp' => te ? 'WhatsApp నంబర్: 6-9 తో మొదలయ్యే 10 అంకెలు.' : 'WhatsApp number: 10 digits starting with 6-9.',
        'owner_only' => te ? 'షాప్ ఓనర్ మాత్రమే లింక్ మార్చగలరు.' : 'Only the shop owner can change the link.',
        _ => e.message(te),
      };
      askodoxPosSnack(context, text);
      if (e.code.startsWith('slug_')) setState(() => _step = 2);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendWhatsApp() async {
    final te = _te;
    final text = askodoxShopLinkShareText(_shop, _url, te);
    final opened = await launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'),
            mode: LaunchMode.externalApplication)
        .catchError((_) => false);
    if (!opened) {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) askodoxPosSnack(context, te ? 'WhatsApp తెరుచుకోలేదు — మెసేజ్ కాపీ చేశాను.' : 'WhatsApp did not open — message copied.');
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _url));
    if (mounted) askodoxPosSnack(context, _te ? 'లింక్ కాపీ అయింది.' : 'Link copied.');
  }

  Future<void> _open() async {
    await launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication).catchError((_) => false);
  }

  void _poster() {
    final te = _te;
    unawaited(showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: AskodoxQrPoster(
            qrKey: const Key('askodoxShopLinkQr'),
            data: _url,
            te: te,
            title: _shop,
            label: _url.replaceFirst('https://', ''),
            instructionEn: 'Scan: menu, prices and order on WhatsApp',
            instructionTe: 'స్కాన్ చేయండి: మెనూ, ధరలు, WhatsApp లో ఆర్డర్',
            footnoteEn: "Pay to the shop's own UPI · ASKODOX never holds money",
            footnoteTe: 'డబ్బు షాప్ సొంత UPI కే · ASKODOX పట్టుకోదు',
            size: 220,
            fileName: 'askodox-shop-link-qr',
          ),
        ),
      ),
    ));
  }

  List<AskodoxStepMore> _more() {
    final te = _te;
    final enabled = _link['enabled'] != false;
    return [
      if (_owner && _made)
        AskodoxStepMore('askodoxShopLinkEdit', te ? 'లింక్ మార్చు' : 'Change the link', Icons.edit_rounded,
            () => setState(() => _step = 1)),
      if (_owner && _made)
        AskodoxStepMore('askodoxShopLinkOnOff', enabled ? (te ? 'లింక్ ఆఫ్ చేయి' : 'Turn the link off') : (te ? 'లింక్ ఆన్ చేయి' : 'Turn the link on'),
            enabled ? Icons.link_off_rounded : Icons.link_rounded, () => _save(enabled: !enabled)),
      AskodoxStepMore('askodoxShopLinkUpi', te ? 'నా QR / ఖాతాలు (UPI)' : 'My QR / accounts (UPI)', Icons.qr_code_2_rounded,
          () => context.push('/me/payment-methods')),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final title = te ? 'నా షాప్ లింక్' : 'My shop link';
    if (_data == null) {
      return AskodoxStepScaffold(
        key: const Key('askodoxShopLink0'),
        title: title,
        body: _error != null ? AskodoxPosError(error: _error!, onRetry: _load) : const Center(child: CircularProgressIndicator()),
      );
    }
    if (!_made && !_owner) {
      return AskodoxStepScaffold(
        key: const Key('askodoxShopLinkNotOwner'),
        title: title,
        sub: _shop,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(te ? 'షాప్ లింక్‌ని షాప్ ఓనర్ మాత్రమే తయారు చేయగలరు.' : 'Only the shop owner can make the shop link.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: askodoxStepMuted)),
          ),
        ),
      );
    }
    return switch (_step) {
      2 => AskodoxStepScaffold(
          key: const Key('askodoxShopLink2'),
          title: title,
          sub: _shop,
          step: 2,
          color: _tone,
          question: te ? 'రంగు & లింక్ పేరు' : 'Colour & link name',
          hint: te ? 'English లో చిన్న పేరు — కస్టమర్లు గుర్తుపెట్టుకునేలా' : 'A short English name customers remember',
          onBack: () => setState(() => _step = 1),
          more: _more(),
          body: _nameStep(te),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxShopLinkSave'),
            label: _made ? (te ? 'మార్పులు సేవ్ చేయి' : 'Save changes') : (te ? 'లింక్ తయారు చేయి' : 'Make the link'),
            icon: Icons.check_rounded,
            color: _tone,
            busy: _busy,
            onPressed: _slugProblem.isEmpty ? () => _save() : null,
            onSpoken: (words) => _slugChanged(askodoxCleanSlug(words)),
          ),
        ),
      3 => AskodoxStepScaffold(
          key: const Key('askodoxShopLink3'),
          title: title,
          sub: _shop,
          step: 3,
          color: _tone,
          more: _more(),
          body: _doneStep(te),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxShopLinkSend'),
            label: te ? 'WhatsApp లో పంపు' : 'Send on WhatsApp',
            icon: Icons.send_rounded,
            color: const Color(0xFF15803D),
            onPressed: _link['enabled'] == false ? null : _sendWhatsApp,
          ),
        ),
      _ => AskodoxStepScaffold(
          key: const Key('askodoxShopLink1'),
          title: title,
          sub: _shop,
          step: 1,
          color: _tone,
          question: te ? 'లింక్‌లో ఏమి చూపించాలి?' : 'What should the link show?',
          hint: te ? 'కస్టమర్ ఫోన్‌లో మీ షాప్ పేజీ — ఉచితం' : "Your shop's page on the customer's phone — free",
          more: _more(),
          body: _showStep(te),
          bottom: AskodoxStepBottom(
            buttonKey: const Key('askodoxShopLinkNext'),
            label: te ? 'తర్వాత' : 'Next',
            icon: Icons.arrow_forward_rounded,
            color: _tone,
            onPressed: () => setState(() => _step = 2),
            onSpoken: (words) => setState(() => _offer.text = words.trim()),
          ),
        ),
    };
  }

  Widget _toggle(String key, IconData icon, String label, String sub, {VoidCallback? onSubTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(border: Border.all(color: askodoxStepLine), borderRadius: BorderRadius.circular(16)),
      child: SwitchListTile(
        key: Key('askodoxShopLinkShow-${key.replaceFirst('show_', '')}'),
        value: _show[key] ?? true,
        onChanged: (v) => setState(() => _show[key] = v),
        secondary: Icon(icon, color: _tone, size: 28),
        title: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: askodoxStepInk)),
        subtitle: onSubTap == null
            ? Text(sub, style: const TextStyle(fontSize: 12.5, color: askodoxStepMuted))
            : InkWell(
                onTap: onSubTap,
                child: Text(sub, style: const TextStyle(fontSize: 12.5, color: askodoxStepInfo, fontWeight: FontWeight.w700))),
      ),
    );
  }

  Widget _showStep(bool te) {
    final hasUpi = _data?['has_upi'] == true;
    final upiId = '${_data?['upi_id'] ?? ''}';
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
      _toggle('show_menu', Icons.restaurant_menu_rounded, te ? 'మెనూ / సరుకులు' : 'Menu / items',
          te ? 'కస్టమర్ ఎంచుకుని WhatsApp లో ఆర్డర్ పంపుతారు' : 'Customers pick and send the order on WhatsApp'),
      if (_show['show_menu'] == true)
        _toggle('show_prices', Icons.currency_rupee_rounded, te ? 'ధరలు' : 'Prices', te ? 'మెనూలో ధరలు చూపించు' : 'Show prices on the menu'),
      _toggle('show_call', Icons.call_rounded, te ? 'కాల్ బటన్' : 'Call button', te ? 'షాప్ ఫోన్‌కి ఒక్క నొక్కుతో' : 'One tap to the shop phone'),
      _toggle('show_map', Icons.place_rounded, te ? 'దారి (మ్యాప్)' : 'Directions (map)', te ? 'షాప్ చిరునామాకి దారి' : 'Directions to the shop address'),
      _toggle(
          'show_pay',
          Icons.qr_code_rounded,
          te ? 'UPI తో కట్టడం' : 'Pay by UPI',
          hasUpi
              ? (te ? 'మీ సొంత UPI: $upiId — డబ్బు నేరుగా మీకే' : 'Your own UPI: $upiId — money comes straight to you')
              : (te ? 'ముందు నా QR / ఖాతాలు లో UPI సేవ్ చేయండి →' : 'First save your UPI in My QR / accounts →'),
          onSubTap: hasUpi ? null : () => context.push('/me/payment-methods')),
      const SizedBox(height: 6),
      TextField(
        key: const Key('askodoxShopLinkOffer'),
        controller: _offer,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: te ? 'ఆఫర్ లైన్ (ఐచ్ఛికం)' : 'Offer line (optional)',
          hintText: te ? 'ఉదా: ఆదివారం 10% తగ్గింపు' : 'e.g. Sunday 10% off',
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        key: const Key('askodoxShopLinkWhatsapp'),
        controller: _whatsapp,
        keyboardType: TextInputType.phone,
        maxLength: 10,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: te ? 'ఆర్డర్లు వచ్చే WhatsApp నంబర్' : 'WhatsApp number for orders',
          border: const OutlineInputBorder(),
          counterText: '',
          helperMaxLines: 3,
          helperText: te
              ? 'కస్టమర్ లింక్‌లో ఐటమ్స్ ఎంచుకుని "WhatsApp లో ఆర్డర్" నొక్కితే, ఆర్డర్ మెసేజ్ ఈ నంబర్‌కే వస్తుంది. ఖాళీగా ఉంటే WhatsApp ఆర్డర్ బటన్ ఉండదు.'
              : 'When a customer picks items on your link and taps "Order on WhatsApp", the order message comes to this number. Empty = no WhatsApp order button.',
        ),
      ),
    ]);
  }

  Widget _nameStep(bool te) {
    final problem = askodoxSlugProblemText(_slugProblem, te);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
      Wrap(alignment: WrapAlignment.center, spacing: 14, runSpacing: 12, children: [
        for (final entry in askodoxShopLinkColors.entries)
          GestureDetector(
            key: Key('askodoxShopLinkColor-${entry.key}'),
            onTap: () => setState(() => _color = entry.key),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Color(entry.value),
                shape: BoxShape.circle,
                border: Border.all(color: _color == entry.key ? askodoxStepInk : Colors.white, width: 3),
                boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 4)],
              ),
              child: _color == entry.key ? const Icon(Icons.check_rounded, color: Colors.white) : null,
            ),
          ),
      ]),
      const SizedBox(height: 20),
      TextField(
        key: const Key('askodoxShopLinkSlug'),
        controller: _slug,
        onChanged: _slugChanged,
        autocorrect: false,
        keyboardType: TextInputType.url,
        maxLength: 30,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        decoration: InputDecoration(
          prefixText: 'askodox.com/s/',
          border: const OutlineInputBorder(),
          errorText: problem,
          helperText: problem == null ? (te ? 'ఈ పేరు ఖాళీగా ఉంది ✓' : 'This name is free ✓') : null,
        ),
      ),
      const SizedBox(height: 14),
      // A small look at the page top: the colour, the shop name and the link.
      Container(
        key: const Key('askodoxShopLinkPreview'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: _tone, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_shop, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('askodox.com/s/${askodoxCleanSlug(_slug.text)}',
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
          if (_offer.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('🎁 ${_offer.text.trim()}', style: const TextStyle(color: Colors.white, fontSize: 13.5)),
          ],
        ]),
      ),
    ]);
  }

  Widget _doneStep(bool te) {
    final stats = askodoxPosMap(_data?['stats']);
    final enabled = _link['enabled'] != false;
    final views = askodoxLinkCount(stats, 'week', const ['view']);
    final orders = askodoxLinkCount(stats, 'week', const ['order_wa', 'order_app']);
    final today = askodoxLinkCount(stats, 'today', const ['view']);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 22, 16, 16), children: [
      Center(child: enabled ? const AskodoxStepDoneMark(size: 96) : const Icon(Icons.link_off_rounded, size: 80, color: askodoxStepBad)),
      const SizedBox(height: 16),
      SelectableText(
        _url.replaceFirst('https://', ''),
        key: const Key('askodoxShopLinkUrl'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: enabled ? _tone : askodoxStepMuted),
      ),
      const SizedBox(height: 6),
      Text(
          enabled
              ? (te ? 'WhatsApp గ్రూపులు, స్టేటస్, Instagram bio లో పెట్టండి — QR పోస్టర్ కౌంటర్ దగ్గర.' : 'Put it in WhatsApp groups, status, Instagram bio — the QR poster at the counter.')
              : (te ? 'లింక్ ఆఫ్‌లో ఉంది — కస్టమర్లకు కనిపించదు (⋮ లో ఆన్ చేయండి).' : 'The link is off — customers cannot open it (turn it on in ⋮).'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: askodoxStepMuted)),
      const SizedBox(height: 18),
      Wrap(alignment: WrapAlignment.spaceEvenly, spacing: 6, runSpacing: 10, children: [
        AskodoxStepRoundAction(
            key: const Key('askodoxShopLinkCopy'), icon: Icons.copy_rounded, label: te ? 'కాపీ' : 'Copy', color: askodoxStepInfo, onTap: _copy),
        AskodoxStepRoundAction(
            key: const Key('askodoxShopLinkPoster'),
            icon: Icons.qr_code_2_rounded,
            label: te ? 'QR పోస్టర్' : 'QR poster',
            color: askodoxStepInk,
            onTap: enabled ? _poster : null),
        AskodoxStepRoundAction(
            key: const Key('askodoxShopLinkOpen'),
            icon: Icons.open_in_new_rounded,
            label: te ? 'చూడు' : 'Open',
            color: _tone,
            onTap: enabled ? _open : null),
      ]),
      const SizedBox(height: 18),
      AskodoxStepBlocks([
        (te ? 'ఈ రోజు చూసినవాళ్లు' : 'Seen today', '$today', askodoxStepInfo),
        (te ? '7 రోజుల్లో' : 'Last 7 days', '$views', askodoxStepInk),
        (te ? 'ఆర్డర్లు (7 రో.)' : 'Orders (7 d)', '$orders', const Color(0xFF15803D)),
      ]),
    ]);
  }
}
