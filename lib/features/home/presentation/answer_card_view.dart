import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/answer_card.dart';

/// ONE phone-screen answer (owner 2026-11-24, design WfPV8AhvZsPFqmwzYpfvap "OneScreen" + "Best - v2"):
/// top = big answer line + voice; middle = up to 4 big icon tabs whose content changes INSIDE the card (sideways
/// swipe cards, tiles, a checklist or steps); photo / SMS checks show a risk meter and what was seen with money /
/// sender / link coloured; quick replies are big buttons whose follow-up shows in the card; bottom = one big action
/// button + mic. The card never grows past [maxHeight]: the middle part takes what is left, nothing scrolls down.
class AskodoxAnswerCardView extends StatefulWidget {
  const AskodoxAnswerCardView({
    super.key,
    required this.card,
    required this.language,
    required this.maxHeight,
    this.extra = '',
    this.speaking = false,
    this.onSpeak,
    this.onMic,
    this.onAsk,
    this.onFeedback,
    this.runAction,
  });

  final AskodoxAnswerCard card;
  final String language;
  final double maxHeight;

  /// Text the app added after the brain's answer (e.g. its next question): shown small under the headline.
  final String extra;
  final bool speaking;
  final VoidCallback? onSpeak;
  final VoidCallback? onMic;
  final ValueChanged<String>? onAsk;
  final ValueChanged<bool>? onFeedback;

  /// Replaces the built-in action runner (tests).
  final Future<void> Function(AskodoxCardAction action)? runAction;

  @override
  State<AskodoxAnswerCardView> createState() => _AskodoxAnswerCardViewState();
}

const _ink = Color(0xFF0F172A);
const _muted = Color(0xFF475569);
const _blue = Color(0xFF2563EB);
const _night = Color(0xFF1E1B3A);

String askodoxCardText(String key, String language) {
  const te = <String, String>{
    'swipe': 'పక్కకి జరపండి →',
    'situation': 'మీ పరిస్థితి ఏది?',
    'useful': 'ఉపయోగపడిందా?',
    'family': 'Family కి పంపండి',
    'money': 'డబ్బు',
    'sender': 'పంపినవారు',
    'link': 'Link – ప్రమాదం',
    'listen': 'వినండి',
    'stop': 'ఆపండి',
    'speak': 'మాట్లాడండి',
    'have_all': 'అన్నీ ఉన్నాయి',
    'still_need': 'ఇంకా కావాలి',
    'donts': 'చేయకూడనివి',
    'thanks': 'ధన్యవాదాలు',
    'no_upi': 'ఈ phone లో UPI / bank app కనిపించలేదు',
    'safe': 'సురక్షితం',
    'careful': 'జాగ్రత్త',
    'danger': 'ప్రమాదం',
  };
  const hi = <String, String>{
    'swipe': 'साइड में खिसकाएँ →',
    'situation': 'आपकी स्थिति क्या है?',
    'useful': 'काम आया?',
    'family': 'परिवार को भेजें',
    'money': 'पैसा',
    'sender': 'भेजने वाला',
    'link': 'लिंक – खतरा',
    'listen': 'सुनें',
    'stop': 'रोकें',
    'speak': 'बोलें',
    'have_all': 'सब है',
    'still_need': 'और चाहिए',
    'donts': 'ये न करें',
    'thanks': 'धन्यवाद',
    'no_upi': 'इस फ़ोन पर UPI / बैंक ऐप नहीं मिला',
    'safe': 'सुरक्षित',
    'careful': 'सावधान',
    'danger': 'खतरा',
  };
  const en = <String, String>{
    'swipe': 'swipe sideways →',
    'situation': 'Which is your situation?',
    'useful': 'Was this useful?',
    'family': 'Send to family',
    'money': 'Money',
    'sender': 'Sender',
    'link': 'Link – danger',
    'listen': 'Listen',
    'stop': 'Stop',
    'speak': 'Speak',
    'have_all': 'You have everything',
    'still_need': 'still needed',
    'donts': "Don'ts",
    'thanks': 'Thank you',
    'no_upi': 'No UPI / bank app found on this phone',
    'safe': 'Safe',
    'careful': 'Careful',
    'danger': 'Danger',
  };
  final table = switch (language) { 'te' => te, 'hi' => hi, _ => en };
  return table[key] ?? en[key] ?? key;
}

IconData askodoxCardTabIcon(String icon) => switch (icon) {
      'money' => Icons.currency_rupee_rounded,
      'types' => Icons.category_outlined,
      'who' => Icons.groups_outlined,
      'papers' => Icons.description_outlined,
      'steps' => Icons.format_list_numbered_rounded,
      'warning' => Icons.warning_amber_rounded,
      'time' => Icons.schedule_rounded,
      'place' => Icons.place_outlined,
      'phone' => Icons.phone_outlined,
      'compare' => Icons.compare_arrows_rounded,
      'tips' => Icons.lightbulb_outline_rounded,
      'rules' => Icons.gavel_rounded,
      'list' => Icons.list_alt_rounded,
      'chart' => Icons.bar_chart_rounded,
      'shop' => Icons.storefront_outlined,
      'food' => Icons.restaurant_rounded,
      'health' => Icons.local_hospital_outlined,
      'travel' => Icons.directions_bus_outlined,
      'legal' => Icons.balance_rounded,
      _ => Icons.info_outline_rounded,
    };

IconData askodoxCardDontIcon(String icon) => switch (icon) {
      'otp' => Icons.lock_outline_rounded,
      'reply' => Icons.comments_disabled_outlined,
      'pin' => Icons.password_rounded,
      'money' => Icons.money_off_rounded,
      'call' => Icons.phone_disabled_outlined,
      'app' => Icons.app_blocking_outlined,
      'share' => Icons.share_outlined,
      'card' => Icons.credit_card_off_outlined,
      'screen' => Icons.stop_screen_share_outlined,
      _ => Icons.link_off_rounded,
    };

/// Background colours of the swipe cards, in turn.
const _cardColors = [Color(0xFFECFDF5), Color(0xFFEFF6FF), Color(0xFFF5F3FF), Color(0xFFFFF7ED)];
const _cardInks = [Color(0xFF15803D), Color(0xFF1D4ED8), Color(0xFF6D28D9), Color(0xFFC2410C)];

({Color bg, Color fg, Color border}) _toneColors(String tone) => switch (tone) {
      'ok' => (bg: const Color(0xFFECFDF5), fg: const Color(0xFF14532D), border: const Color(0xFF16A34A)),
      'warn' => (bg: const Color(0xFFFFF7ED), fg: const Color(0xFF9A3412), border: const Color(0xFFFB923C)),
      'danger' => (bg: const Color(0xFFFEF2F2), fg: const Color(0xFF991B1B), border: const Color(0xFFDC2626)),
      _ => (bg: const Color(0xFFEFF6FF), fg: const Color(0xFF1E3A8A), border: const Color(0xFFC7D2FE)),
    };

({Color bg, Color fg}) _markColors(String? kind) => switch (kind) {
      'money' => (bg: const Color(0xFFDBEAFE), fg: const Color(0xFF1E3A8A)),
      'sender' => (bg: const Color(0xFFEDE9FE), fg: const Color(0xFF5B21B6)),
      'link' => (bg: const Color(0xFFFEE2E2), fg: const Color(0xFF991B1B)),
      'date' => (bg: const Color(0xFFFEF3C7), fg: const Color(0xFF92400E)),
      'number' => (bg: const Color(0xFFE0F2FE), fg: const Color(0xFF075985)),
      _ => (bg: Colors.transparent, fg: const Color(0xFF334155)),
    };

class _AskodoxAnswerCardViewState extends State<AskodoxAnswerCardView> {
  int _tab = 0;
  int? _picked;
  int _page = 0;
  final Set<int> _ticked = {};
  bool? _feedback;
  final Map<String, PageController> _pages = {};

  PageController _pagesOf(String id) => _pages.putIfAbsent(id, () => PageController(viewportFraction: 0.8));

  @override
  void dispose() {
    for (final c in _pages.values) {
      c.dispose();
    }
    super.dispose();
  }

  AskodoxAnswerCard get _card => widget.card;
  String _t(String key) => askodoxCardText(key, widget.language);

  @override
  void didUpdateWidget(covariant AskodoxAnswerCardView old) {
    super.didUpdateWidget(old);
    if (!identical(old.card, widget.card)) {
      _tab = 0;
      _picked = null;
      _page = 0;
      _ticked.clear();
    }
  }

  Future<void> _run(AskodoxCardAction action) async {
    if (action.kind == 'ask') {
      widget.onAsk?.call(action.value.isEmpty ? action.label : action.value);
      return;
    }
    if (widget.runAction != null) return widget.runAction!(action);
    await askodoxRunCardAction(context, action,
        language: widget.language, shareText: askodoxCardShareText(_card, telugu: widget.language == 'te'),
        smsBody: _card.seenText);
  }

  @override
  Widget build(BuildContext context) {
    final card = _card;
    final picked = _picked == null ? null : card.replies[_picked!];
    final tall = RegExp(r'[ఀ-෿ऀ-ॿঀ-૿଀-୿]').hasMatch(card.headline);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: DecoratedBox(
        key: const Key('askodoxAnswerCard'),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x120F172A), blurRadius: 10, offset: Offset(0, 2))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(tall),
              if (card.seenText.isNotEmpty) _seen(),
              if (card.tabs.length >= 2 && picked == null) _tabBar(),
              Flexible(child: _body(picked)),
              if (card.replies.isNotEmpty) _replies(),
              _bottom(),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool tall) {
    final card = _card;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (card.risk != null) _riskRow(card.risk!),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (card.label.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(card.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF15803D))),
                ),
              Text(card.headline,
                  key: const Key('askodoxAnswerCardHeadline'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 19, height: tall ? 1.45 : 1.3, fontWeight: FontWeight.w800, color: _ink)),
              if (widget.extra.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(widget.extra,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, height: 1.4, color: _muted, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          const SizedBox(width: 10),
          Semantics(
            button: true,
            label: widget.speaking ? _t('stop') : _t('listen'),
            child: Material(
              color: widget.speaking ? const Color(0xFF4F46E5) : _night,
              shape: const CircleBorder(),
              child: InkWell(
                key: const Key('askodoxAnswerCardVoice'),
                customBorder: const CircleBorder(),
                onTap: widget.onSpeak,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(widget.speaking ? Icons.pause_rounded : Icons.volume_up_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _riskRow(String risk) {
    final (label, fg, bg, filled) = switch (risk) {
      'safe' => (_t('safe'), const Color(0xFF166534), const Color(0xFFDCFCE7), 1),
      'danger' => (_t('danger'), const Color(0xFF991B1B), const Color(0xFFFEE2E2), 3),
      _ => (_t('careful'), const Color(0xFF92400E), const Color(0xFFFFF4E5), 2),
    };
    const segment = [Color(0xFF16A34A), Color(0xFFF59E0B), Color(0xFFDC2626)];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        label: _card.riskLabel.isNotEmpty ? _card.riskLabel : label,
        child: Row(key: ValueKey('askodoxAnswerCardRisk-$risk'), children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
            child: Text(_card.riskLabel.isNotEmpty ? _card.riskLabel : label,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
          ),
          const SizedBox(width: 8),
          for (var i = 0; i < 3; i++) ...[
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                    color: i < filled ? segment[i] : const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(3)),
              ),
            ),
            if (i < 2) const SizedBox(width: 4),
          ],
        ]),
      ),
    );
  }

  Widget _seen() {
    final card = _card;
    final pieces = askodoxMarkedPieces(card.seenText, card.seenMarks);
    final kinds = card.seenMarks.map((m) => m.kind).toSet();
    return Container(
      key: const Key('askodoxAnswerCardSeen'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (card.seenTitle.isNotEmpty)
          Text(card.seenTitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _muted)),
        const SizedBox(height: 4),
        Text.rich(
          TextSpan(children: [
            for (final piece in pieces)
              TextSpan(
                text: piece.text,
                style: piece.kind == null
                    ? null
                    : TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _markColors(piece.kind).fg,
                        backgroundColor: _markColors(piece.kind).bg,
                        decoration: piece.kind == 'link' ? TextDecoration.underline : null,
                        decorationColor: const Color(0xFFDC2626)),
              ),
          ]),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFF334155)),
        ),
        if (kinds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 12, runSpacing: 2, children: [
              for (final kind in const ['money', 'sender', 'link'])
                if (kinds.contains(kind))
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration:
                            BoxDecoration(color: _markColors(kind).fg.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 5),
                    Text(_t(kind),
                        style: TextStyle(
                            fontSize: 12,
                            color: kind == 'link' ? const Color(0xFF991B1B) : _muted,
                            fontWeight: kind == 'link' ? FontWeight.w700 : FontWeight.w500)),
                  ]),
            ]),
          ),
      ]),
    );
  }

  Widget _tabBar() {
    final tabs = _card.tabs;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(children: [
        for (final (i, tab) in tabs.indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              selected: i == _tab,
              button: true,
              child: Material(
                color: i == _tab ? _blue : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  key: ValueKey('askodoxAnswerCardTab-$i'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() {
                    _tab = i;
                    _page = _pages[tab.id]?.hasClients == true ? (_pages[tab.id]!.page ?? 0).round() : 0;
                  }),
                  child: SizedBox(
                    height: 68,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                            color: i == _tab ? Colors.white.withValues(alpha: 0.2) : Colors.white,
                            borderRadius: BorderRadius.circular(11)),
                        child: Icon(askodoxCardTabIcon(tab.icon),
                            size: 18, color: i == _tab ? Colors.white : const Color(0xFF334155)),
                      ),
                      const SizedBox(height: 5),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(tab.label,
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: i == _tab ? Colors.white : const Color(0xFF334155))),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  /// The middle: a chosen reply's follow-up, else the open tab, else the don'ts. Takes only the room left.
  Widget _body(AskodoxCardReply? picked) {
    final card = _card;
    final tab = card.tabs.isEmpty ? null : card.tabs[_tab.clamp(0, card.tabs.length - 1)];
    if (picked == null && tab == null && card.donts.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final preferred = picked != null
          ? 64.0 + (picked.actions.isEmpty ? 0 : 56) + (picked.text.length > 80 ? 22 : 0)
          : tab == null
              ? 92.0
              : switch (tab.style) {
                  'cards' || 'steps' => 196.0,
                  'grid' => 30.0 + ((tab.items.length + 2) ~/ 3) * 58,
                  'checklist' => 52.0 + ((tab.items.length + 1) ~/ 2) * 56,
                  _ => 130.0,
                };
      final height = box.maxHeight.isFinite ? preferred.clamp(0.0, box.maxHeight) : preferred;
      if (height < 60) return const SizedBox.shrink();
      return Container(
        height: height,
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF0F4)))),
        padding: const EdgeInsets.only(top: 10),
        child: picked != null
            ? _followUp(picked)
            : tab == null
                ? _donts()
                : _tabContent(tab),
      );
    });
  }

  /// [child] at its natural height, scaled down (never cut, never an overflow) when the room is smaller.
  Widget _fit(Widget child, {Alignment alignment = Alignment.topLeft}) => LayoutBuilder(
        builder: (context, box) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: SizedBox(width: box.maxWidth.isFinite ? box.maxWidth : 300, child: child),
        ),
      );

  Widget _title(String text, {String hint = ''}) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(text: text),
            if (hint.isNotEmpty)
              TextSpan(text: ' · $hint', style: const TextStyle(fontWeight: FontWeight.w400, color: Color(0xFF64748B))),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink),
        ),
      );

  Widget _tabContent(AskodoxCardTab tab) {
    final title = tab.title.isNotEmpty ? tab.title : (_card.tabs.length < 2 ? tab.label : '');
    switch (tab.style) {
      case 'cards' || 'steps':
        if (tab.items.isEmpty) return _note(tab, title);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title.isNotEmpty || tab.items.length > 1) _title(title, hint: tab.items.length > 1 ? _t('swipe') : ''),
          Expanded(
            child: PageView.builder(
              key: ValueKey('askodoxAnswerCardPages-${tab.id}'),
              controller: _pagesOf(tab.id),
              padEnds: false,
              itemCount: tab.items.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => _swipeCard(tab, i),
            ),
          ),
          if (tab.items.length > 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < tab.items.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: i == _page ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                        color: i == _page ? _blue : const Color(0xFFCBD5E1), borderRadius: BorderRadius.circular(3)),
                  ),
              ]),
            ),
        ]);
      case 'grid':
        if (tab.items.isEmpty) return _note(tab, title);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title.isNotEmpty) _title(title),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _rows(tab.items.length, 3, (i) {
                final item = tab.items[i];
                return Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(14)),
                  child: Text(item.title.isNotEmpty ? item.title : item.value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink)),
                );
              }),
            ),
          ),
        ]);
      case 'checklist':
        if (tab.items.isEmpty) return _note(tab, title);
        final missing = tab.items.length - _ticked.length;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title.isNotEmpty) _title(title),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: _rows(tab.items.length, 2, (i) {
                final on = _ticked.contains(i);
                return Material(
                  color: on ? const Color(0xFFECFDF5) : Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: on ? const Color(0xFF16A34A) : const Color(0xFFCBD5E1), width: 1.5)),
                  child: InkWell(
                    key: ValueKey('askodoxAnswerCardCheck-$i'),
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => on ? _ticked.remove(i) : _ticked.add(i)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        Icon(on ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                            size: 20, color: on ? const Color(0xFF16A34A) : const Color(0xFF94A3B8)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(tab.items[i].title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink)),
                        ),
                      ]),
                    ),
                  ),
                );
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(missing <= 0 ? '✓ ${_t('have_all')}' : '$missing ${_t('still_need')}',
                key: const Key('askodoxAnswerCardChecklistCount'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _muted)),
          ),
        ]);
      default:
        return _note(tab, title);
    }
  }

  Widget _note(AskodoxCardTab tab, String title) {
    final text = tab.note.isNotEmpty
        ? tab.note
        : tab.items.map((i) => [i.title, i.value, i.body].where((x) => x.isNotEmpty).join(' – ')).join('\n');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (title.isNotEmpty) _title(title),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(text,
              overflow: TextOverflow.fade,
              style: const TextStyle(fontSize: 15, height: 1.5, color: Color(0xFF334155))),
        ),
      ),
    ]);
  }

  /// [count] tiles in rows of [perRow]; rows share the height, so nothing ever overflows.
  Widget _rows(int count, int perRow, Widget Function(int i) tile) {
    final rows = (count + perRow - 1) ~/ perRow;
    return Column(children: [
      for (var r = 0; r < rows; r++) ...[
        if (r > 0) const SizedBox(height: 8),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (var c = 0; c < perRow; c++) ...[
              if (c > 0) const SizedBox(width: 8),
              Expanded(child: r * perRow + c < count ? tile(r * perRow + c) : const SizedBox.shrink()),
            ],
          ]),
        ),
      ],
    ]);
  }

  Widget _swipeCard(AskodoxCardTab tab, int i) {
    final item = tab.items[i];
    final steps = tab.style == 'steps';
    final last = steps && i == tab.items.length - 1;
    final bg = steps ? (last ? _cardColors[0] : _cardColors[1]) : _cardColors[i % _cardColors.length];
    final ink = steps ? (last ? const Color(0xFF16A34A) : _blue) : _cardInks[i % _cardInks.length];
    return Padding(
      padding: EdgeInsets.only(left: i == 0 ? 16 : 5, right: 5),
      child: Container(
        key: ValueKey('askodoxAnswerCardItem-${tab.id}-$i'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18)),
        child: _fit(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (steps)
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: ink, shape: BoxShape.circle),
              child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            )
          else if (item.title.isNotEmpty && item.value.isNotEmpty)
            Text('${i + 1} · ${item.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: ink)),
          const SizedBox(height: 6),
          if (item.value.isNotEmpty)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(item.value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _ink)),
            )
          else if (item.title.isNotEmpty)
            Text(item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: _ink, height: 1.3)),
          if (item.sub.isNotEmpty)
            Text(item.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: _muted)),
          if (item.body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(item.body,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14.5, height: 1.45, color: Color(0xFF334155))),
          ],
        ])),
      ),
    );
  }

  Widget _donts() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, d) in _card.donts.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    key: ValueKey('askodoxAnswerCardDont-$i'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFFFDF0F0), borderRadius: BorderRadius.circular(14)),
                    child: _fit(
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(askodoxCardDontIcon(d.icon), size: 22, color: const Color(0xFFB91C1C)),
                          const SizedBox(height: 4),
                          Text(d.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF7F1D1D))),
                        ]),
                        alignment: Alignment.center),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ]);

  Widget _followUp(AskodoxCardReply reply) {
    final look = _toneColors(reply.tone);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        key: const Key('askodoxAnswerCardFollowUp'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: look.bg, borderRadius: BorderRadius.circular(14)),
        child: _fit(Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (reply.text.isNotEmpty)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(
                    switch (reply.tone) {
                      'ok' => Icons.check_circle_outline_rounded,
                      'danger' => Icons.error_outline_rounded,
                      'warn' => Icons.warning_amber_rounded,
                      _ => Icons.info_outline_rounded,
                    },
                    size: 20,
                    color: look.fg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(reply.text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14.5, height: 1.45, color: look.fg, fontWeight: FontWeight.w600)),
                ),
              ]),
          if (reply.actions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(children: [
              for (final (i, action) in reply.actions.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: i == 0
                        ? FilledButton(
                            key: ValueKey('askodoxAnswerCardFollowAction-$i'),
                            style: FilledButton.styleFrom(
                                backgroundColor: look.border == const Color(0xFFC7D2FE) ? _blue : look.border,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 6)),
                            onPressed: () => _run(action),
                            child: _buttonLabel(action),
                          )
                        : OutlinedButton(
                            key: ValueKey('askodoxAnswerCardFollowAction-$i'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: look.fg,
                                side: BorderSide(color: look.border, width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(horizontal: 6)),
                            onPressed: () => _run(action),
                            child: _buttonLabel(action),
                          ),
                  ),
                ),
              ],
            ]),
          ],
        ])),
      ),
    );
  }

  Widget _buttonLabel(AskodoxCardAction action) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(askodoxCardActionIcon(action.kind), size: 18),
          const SizedBox(width: 6),
          Text(action.label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ]),
      );

  Widget _replies() {
    final card = _card;
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF0F4)))),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (card.isCheck)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(_t('situation'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _ink)),
          ),
        // One row of equal big buttons (never a wrap of small chips): the card keeps one height in every language.
        Row(children: [
          for (final (i, reply) in card.replies.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _replyButton(i, reply)),
          ],
        ]),
      ]),
    );
  }

  Widget _replyButton(int i, AskodoxCardReply reply) {
    final on = _picked == i;
    final look = _toneColors(reply.tone);
    final danger = reply.tone == 'danger';
    return SizedBox(
      height: 50,
      child: Material(
        color: on ? (danger ? const Color(0xFFB91C1C) : _blue) : Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16), side: BorderSide(color: look.border, width: 1.5)),
        child: InkWell(
          key: ValueKey('askodoxAnswerCardReply-$i'),
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (reply.answersInCard) {
              setState(() => _picked = on ? null : i);
            } else {
              widget.onAsk?.call(reply.label);
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Center(
              child: Text(reply.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: on ? Colors.white : (danger ? const Color(0xFF991B1B) : const Color(0xFF1E3A8A)))),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottom() {
    final primary = _card.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Row(children: [
        if (primary != null)
          Expanded(
            child: SizedBox(
              height: 54,
              child: FilledButton(
                key: const Key('askodoxAnswerCardPrimary'),
                style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 10)),
                onPressed: () => _run(primary),
                child: _buttonLabel(primary),
              ),
            ),
          )
        else
          const Spacer(),
        const SizedBox(width: 10),
        Semantics(
          button: true,
          label: _t('speak'),
          child: Material(
            color: _night,
            shape: const CircleBorder(),
            child: InkWell(
              key: const Key('askodoxAnswerCardMic'),
              customBorder: const CircleBorder(),
              onTap: widget.onMic,
              child: const SizedBox(width: 54, height: 54, child: Icon(Icons.mic_rounded, color: Colors.white)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _footer() {
    final card = _card;
    return Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFEEF0F4)))),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Row(children: [
        Flexible(
          child: Text(_feedback == null ? _t('useful') : _t('thanks'),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
        ),
        IconButton(
          key: const Key('askodoxAnswerCardUseful'),
          tooltip: _t('useful'),
          visualDensity: VisualDensity.compact,
          icon: Icon(_feedback == true ? Icons.thumb_up_alt_rounded : Icons.thumb_up_alt_outlined,
              size: 18, color: _feedback == true ? _blue : const Color(0xFF64748B)),
          onPressed: _feedback != null
              ? null
              : () {
                  setState(() => _feedback = true);
                  widget.onFeedback?.call(true);
                },
        ),
        IconButton(
          key: const Key('askodoxAnswerCardNotUseful'),
          visualDensity: VisualDensity.compact,
          icon: Icon(_feedback == false ? Icons.thumb_down_alt_rounded : Icons.thumb_down_alt_outlined,
              size: 18, color: const Color(0xFF64748B)),
          onPressed: _feedback != null
              ? null
              : () {
                  setState(() => _feedback = false);
                  widget.onFeedback?.call(false);
                },
        ),
        if (card.share)
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: TextButton.icon(
            key: const Key('askodoxAnswerCardShare'),
            style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF334155),
                backgroundColor: const Color(0xFFF1F5F9),
                shape: const StadiumBorder(),
                minimumSize: const Size(0, 40)),
            onPressed: () => _run(AskodoxCardAction(kind: 'share', label: _t('family'))),
            icon: const Icon(Icons.share_rounded, size: 16),
            label: Text(_t('family'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

IconData askodoxCardActionIcon(String kind) => switch (kind) {
      'call' => Icons.call_rounded,
      'bank_help' => Icons.account_balance_rounded,
      'open_upi' => Icons.account_balance_wallet_rounded,
      'open_url' => Icons.open_in_new_rounded,
      'sms' => Icons.report_gmailerrorred_rounded,
      'block_help' => Icons.block_rounded,
      'share' => Icons.share_rounded,
      _ => Icons.chat_bubble_outline_rounded,
    };

const _device = MethodChannel('com.askodox.app/device');

/// Runs one card button. Only fixed kinds; numbers / links were checked on the server and again in
/// [AskodoxCardAction.fromJson]. Nothing is ever paid, sent or blocked by ASKODOX itself: the person's own dialer,
/// SMS app, bank / UPI app or share sheet opens.
Future<void> askodoxRunCardAction(BuildContext context, AskodoxCardAction action,
    {required String language, String shareText = '', String smsBody = ''}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  Future<void> open(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  switch (action.kind) {
    case 'call':
      await open(Uri(scheme: 'tel', path: action.value));
    case 'sms':
      final body = smsBody.isEmpty ? '' : '?body=${Uri.encodeComponent(smsBody)}';
      await open(Uri.parse('sms:${action.value}$body'));
    case 'open_url':
      final uri = Uri.tryParse(action.value);
      if (uri != null && uri.scheme == 'https') await open(uri);
    case 'open_upi':
      var opened = false;
      try {
        opened = await _device.invokeMethod<bool>('openUpiApps', {'title': action.label}) ?? false;
      } catch (_) {}
      if (!opened) messenger?.showSnackBar(SnackBar(content: Text(askodoxCardText('no_upi', language))));
    case 'share':
      try {
        await _device.invokeMethod<bool>('shareText', {'text': shareText, 'title': action.label});
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: shareText));
      }
    case 'bank_help' || 'block_help':
      if (context.mounted) await askodoxShowCardHelp(context, action.kind, language: language);
  }
}

/// How-to sheets for things only the person's own phone / bank can do (ASKODOX cannot block a number or call
/// "your" bank for you): short steps for every phone and bank, plus the buttons that CAN help right now.
Future<void> askodoxShowCardHelp(BuildContext context, String kind, {required String language}) {
  final te = language == 'te';
  final hi = language == 'hi';
  final bank = kind == 'bank_help';
  final title = bank
      ? (te ? 'మీ bank కి వెంటనే' : hi ? 'तुरंत अपने बैंक को' : 'Call your bank now')
      : (te ? 'ఈ number ని block చేయండి' : hi ? 'इस नंबर को ब्लॉक करें' : 'Block this sender');
  final steps = bank
      ? (te
          ? [
              'మీ debit card వెనుక లేదా passbook మొదటి పేజీలో ఉన్న customer care number కి call చేయండి.',
              'Bank / UPI app లో "Block card" లేదా "UPI off" నొక్కండి.',
              'డబ్బు పోయింటే 1930 కి కూడా call చేయండి – మొదటి గంట చాలా ముఖ్యం.',
            ]
          : hi
              ? [
                  'डेबिट कार्ड के पीछे या पासबुक के पहले पेज पर लिखे कस्टमर केयर नंबर पर कॉल करें।',
                  'बैंक / UPI ऐप में "Block card" या "UPI off" दबाएँ।',
                  'पैसा गया हो तो 1930 पर भी कॉल करें – पहला घंटा सबसे ज़रूरी है।',
                ]
              : [
                  'Call the customer care number on the back of your debit card or the first page of your passbook.',
                  'In your bank / UPI app tap "Block card" or turn UPI off.',
                  'If money is gone, also call 1930 – the first hour matters most.',
                ])
      : (te
          ? [
              'Google Messages: chat ని నొక్కి పట్టుకోండి → Block → "Report spam" టిక్ → OK.',
              'Samsung Messages: chat తెరిచి ⋮ → Block number.',
              'Xiaomi / Redmi / Vivo / Oppo / Realme: chat తెరిచి ⋮ లేదా ⓘ → Block.',
              'iPhone: sender పేరు నొక్కి → Info → Block this Caller.',
            ]
          : hi
              ? [
                  'Google Messages: चैट दबाकर रखें → Block → "Report spam" टिक → OK.',
                  'Samsung Messages: चैट खोलें → ⋮ → Block number.',
                  'Xiaomi / Redmi / Vivo / Oppo / Realme: चैट खोलें → ⋮ या ⓘ → Block.',
                  'iPhone: भेजने वाले के नाम पर टैप → Info → Block this Caller.',
                ]
              : [
                  'Google Messages: press and hold the chat → Block → tick "Report spam" → OK.',
                  'Samsung Messages: open the chat → ⋮ → Block number.',
                  'Xiaomi / Redmi / Vivo / Oppo / Realme: open the chat → ⋮ or ⓘ → Block.',
                  'iPhone: tap the sender → Info → Block this Caller.',
                ]);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          for (final (i, step) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(radius: 12, child: Text('${i + 1}', style: const TextStyle(fontSize: 12))),
                const SizedBox(width: 10),
                Expanded(child: Text(step, style: const TextStyle(fontSize: 15, height: 1.45))),
              ]),
            ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                key: Key(bank ? 'askodoxCardHelpDial' : 'askodoxCardHelpSpam'),
                onPressed: () => launchUrl(
                    bank ? Uri(scheme: 'tel', path: '') : Uri.parse('https://sancharsaathi.gov.in/sfc/'),
                    mode: LaunchMode.externalApplication),
                icon: Icon(bank ? Icons.dialpad_rounded : Icons.report_rounded),
                label: Text(bank ? (te ? 'Dialer తెరవండి' : 'Open dialer') : 'Chakshu report'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => launchUrl(Uri(scheme: 'tel', path: '1930'), mode: LaunchMode.externalApplication),
                icon: const Icon(Icons.call_rounded),
                label: const Text('1930'),
              ),
            ),
          ]),
        ]),
      ),
    ),
  );
}

/// The card while the answer is still being written: the spoken part grows, a quiet bar shows the rest is coming.
class AskodoxAnswerCardPending extends StatelessWidget {
  const AskodoxAnswerCardPending({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Column(
        key: const Key('askodoxAnswerCardPending'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(fontSize: 18, height: 1.45, fontWeight: FontWeight.w800, color: _ink)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: const LinearProgressIndicator(minHeight: 4, color: _blue, backgroundColor: Color(0xFFE2E8F0)),
          ),
        ],
      );
}
