/// One-screen answer card (owner 2026-11-24, design artifact WfPV8AhvZsPFqmwzYpfvap "OneScreen" + "Best - v2").
///
/// The backend (`answer_card.py`) returns `card` next to the plain `reply` when this app sends the `answer_card`
/// capability. The reply itself is written in two parts: the short part that is shown big and spoken, a line
/// `[[more]]`, then the details (drawn as tabs). Everything here is pure (no widgets) so it is unit tested.
library;

const askodoxAnswerCardMark = '[[more]]';

/// The part of a reply shown big and read aloud (before the mark); the whole reply when there is no mark.
String askodoxSpokenPart(String reply) {
  final at = reply.indexOf(askodoxAnswerCardMark);
  return (at >= 0 ? reply.substring(0, at) : reply).trim();
}

/// The reply as plain text (old turns, copy, history): the mark becomes a paragraph break.
String askodoxWithoutCardMark(String reply) =>
    reply.replaceAll(RegExp(r'\n?[ \t]*\[\[more\]\][ \t]*\n?'), '\n\n').trim();

/// While a reply streams in: only the spoken part, and whether the spoken part is complete (the mark arrived).
({String text, bool complete}) askodoxStreamingSpokenPart(String soFar) {
  final at = soFar.indexOf(askodoxAnswerCardMark);
  if (at >= 0) return (text: soFar.substring(0, at).trim(), complete: true);
  // Never show half of the mark ("[[mo") while it is being written.
  final partial = RegExp(r'\[(\[(m(o(r(e(\])?)?)?)?)?)?)?$').firstMatch(soFar);
  return (text: (partial == null ? soFar : soFar.substring(0, partial.start)).trimRight(), complete: false);
}

String _s(Object? v) => v is String ? v.trim() : (v is num ? '$v' : '');

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? [for (final x in v) if (x is Map) Map<String, dynamic>.from(x)] : const [];

/// One button the card may show. Kinds are fixed (the server checked every value).
class AskodoxCardAction {
  const AskodoxCardAction({required this.kind, required this.label, this.value = ''});

  final String kind; // call | open_url | open_upi | sms | ask | bank_help | block_help | share
  final String label;
  final String value;

  static const kinds = {'call', 'open_url', 'open_upi', 'sms', 'ask', 'bank_help', 'block_help', 'share'};

  static AskodoxCardAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final kind = _s(raw['kind']);
    final label = _s(raw['label']);
    if (!kinds.contains(kind) || label.isEmpty) return null;
    final value = _s(raw['value']);
    if (kind == 'call' && !RegExp(r'^\d{3,13}$').hasMatch(value)) return null;
    if (kind == 'sms' && !RegExp(r'^\d{3,6}$').hasMatch(value)) return null;
    if (kind == 'open_url' && !value.startsWith('https://')) return null;
    return AskodoxCardAction(kind: kind, label: label, value: value);
  }
}

class AskodoxCardItem {
  const AskodoxCardItem({this.title = '', this.value = '', this.sub = '', this.body = ''});

  final String title;
  final String value;
  final String sub;
  final String body;
}

class AskodoxCardTab {
  const AskodoxCardTab({
    required this.id,
    required this.label,
    this.icon = 'info',
    this.style = 'cards',
    this.title = '',
    this.items = const [],
    this.note = '',
  });

  final String id;
  final String label;
  final String icon;
  final String style; // cards | grid | checklist | steps | text
  final String title;
  final List<AskodoxCardItem> items;
  final String note;
}

class AskodoxCardMark {
  const AskodoxCardMark(this.text, this.kind);

  final String text;
  final String kind; // money | sender | link | date | number
}

class AskodoxCardReply {
  const AskodoxCardReply({required this.label, this.tone = 'neutral', this.text = '', this.actions = const []});

  final String label;
  final String tone; // ok | warn | danger | neutral
  /// Shown INSIDE the card when tapped; empty = the label is sent to the assistant as the next message.
  final String text;
  final List<AskodoxCardAction> actions;

  bool get answersInCard => text.isNotEmpty || actions.isNotEmpty;
}

class AskodoxAnswerCard {
  const AskodoxAnswerCard({
    required this.headline,
    this.kind = 'answer',
    this.label = '',
    this.speak = '',
    this.risk,
    this.riskLabel = '',
    this.seenTitle = '',
    this.seenText = '',
    this.seenMarks = const [],
    this.tabs = const [],
    this.donts = const [],
    this.replies = const [],
    this.primary,
    this.actions = const [],
    this.share = false,
  });

  final String kind; // answer | check
  final String label;
  final String headline;
  final String speak;
  final String? risk; // safe | careful | danger (checks only)
  final String riskLabel;
  final String seenTitle;
  final String seenText;
  final List<AskodoxCardMark> seenMarks;
  final List<AskodoxCardTab> tabs;
  final List<({String icon, String text})> donts;
  final List<AskodoxCardReply> replies;
  final AskodoxCardAction? primary;
  final List<AskodoxCardAction> actions;
  final bool share;

  bool get isCheck => kind == 'check';

  /// What the voice says for this card.
  String get spokenText => speak.isNotEmpty ? speak : headline;

  static AskodoxAnswerCard? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final headline = _s(json['headline']);
    if (headline.isEmpty) return null;
    final kind = _s(json['kind']) == 'check' ? 'check' : 'answer';
    final seen = json['seen'] is Map ? Map<String, dynamic>.from(json['seen'] as Map) : const <String, dynamic>{};
    final seenText = _s(seen['text']);
    final risk = _s(json['risk']);
    return AskodoxAnswerCard(
      kind: kind,
      label: _s(json['label']),
      headline: headline,
      speak: _s(json['speak']),
      risk: kind == 'check' && const {'safe', 'careful', 'danger'}.contains(risk) ? risk : null,
      riskLabel: _s(json['risk_label']),
      seenTitle: _s(seen['title']),
      seenText: seenText,
      seenMarks: [
        for (final m in _maps(seen['marks']))
          if (_s(m['text']).isNotEmpty && seenText.contains(_s(m['text'])))
            AskodoxCardMark(_s(m['text']), _s(m['kind'])),
      ],
      tabs: [
        for (final t in _maps(json['tabs']).take(4))
          if (_s(t['label']).isNotEmpty)
            AskodoxCardTab(
              id: _s(t['id']).isEmpty ? _s(t['label']) : _s(t['id']),
              label: _s(t['label']),
              icon: _s(t['icon']).isEmpty ? 'info' : _s(t['icon']),
              style: _s(t['style']).isEmpty ? 'cards' : _s(t['style']),
              title: _s(t['title']),
              note: _s(t['note']),
              items: [
                for (final i in _maps(t['items']).take(6))
                  AskodoxCardItem(title: _s(i['title']), value: _s(i['value']), sub: _s(i['sub']), body: _s(i['body'])),
              ],
            ),
      ],
      donts: [
        for (final d in _maps(json['donts']).take(3))
          if (_s(d['text']).isNotEmpty) (icon: _s(d['icon']), text: _s(d['text'])),
      ],
      replies: [
        for (final r in _maps(json['replies']).take(4))
          if (_s(r['label']).isNotEmpty)
            AskodoxCardReply(
              label: _s(r['label']),
              tone: _s(r['tone']).isEmpty ? 'neutral' : _s(r['tone']),
              text: _s(r['text']),
              actions: [
                for (final a in (r['actions'] is List ? r['actions'] as List : const []).take(2))
                  if (AskodoxCardAction.fromJson(a) case final action?) action,
              ],
            ),
      ],
      primary: AskodoxCardAction.fromJson(json['primary']),
      actions: [
        for (final a in (json['actions'] is List ? json['actions'] as List : const []).take(2))
          if (AskodoxCardAction.fromJson(a) case final action?) action,
      ],
      share: json['share'] == true,
    );
  }
}

/// [text] split into plain and marked pieces (money / sender / link ...), in order, for the coloured SMS view.
List<({String text, String? kind})> askodoxMarkedPieces(String text, List<AskodoxCardMark> marks) {
  final spans = <({int start, int end, String kind})>[];
  for (final mark in marks) {
    var from = 0;
    while (true) {
      final at = text.indexOf(mark.text, from);
      if (at < 0) break;
      final end = at + mark.text.length;
      if (!spans.any((s) => at < s.end && end > s.start)) spans.add((start: at, end: end, kind: mark.kind));
      from = end;
    }
  }
  spans.sort((a, b) => a.start.compareTo(b.start));
  final out = <({String text, String? kind})>[];
  var at = 0;
  for (final span in spans) {
    if (span.start > at) out.add((text: text.substring(at, span.start), kind: null));
    out.add((text: text.substring(span.start, span.end), kind: span.kind));
    at = span.end;
  }
  if (at < text.length) out.add((text: text.substring(at), kind: null));
  return out;
}

/// The text sent when "Send to family" is tapped: the warning, what was seen, the don'ts. No links are added.
String askodoxCardShareText(AskodoxAnswerCard card, {required bool telugu}) {
  final lines = <String>[
    '⚠️ ${card.headline}',
    if (card.seenText.isNotEmpty) '"${card.seenText.replaceAll(RegExp(r'https?://\S+'), '[link]')}"',
    for (final d in card.donts) '❌ ${d.text}',
    telugu ? '— ASKODOX లో check చేశాను' : '— checked on ASKODOX',
  ];
  return lines.join('\n');
}

/// What is spoken for a reply: only the short part when the reply has details after [[more]].
String askodoxCardSpokenReply(String reply) =>
    reply.contains(askodoxAnswerCardMark) ? askodoxSpokenPart(reply) : reply;
