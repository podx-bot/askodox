import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../home/domain/conversation_language.dart';
import '../../matching/data/universal_match_repository.dart';
import '../data/benefits.dart';

String _money(double value) => '₹${value == value.roundToDouble() ? value.toStringAsFixed(0) : value.toStringAsFixed(2)}';

/// "₹2,000 instant discount", "6% cashback", "free installation" -- facts
/// from the offer only; nothing computed that the offer does not state.
String askodoxBenefitHeadline(AskodoxBenefit b, String lang) {
  String l(String key) => askodoxChatLabel(key, lang);
  if (b.kind == 'gift' && (b.freeBenefit ?? '').isNotEmpty) return '${l('gift')} ${b.freeBenefit}';
  if (b.value != null) return '${_money(b.value!)} ${l(b.kind)}';
  if (b.percent != null) return '${b.percent!.toStringAsFixed(0)}% ${l(b.kind)}';
  return l(b.kind);
}

/// Compact chip on a result card: "2 offer(s) · up to ₹2,000".
class AskodoxBenefitsChip extends ConsumerWidget {
  const AskodoxBenefitsChip({super.key, required this.match, required this.lang});

  final UniversalMatch match;
  final String lang;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offers = AskodoxBenefit.listFrom(match.benefits);
    if (offers.isEmpty) return const SizedBox.shrink();
    final more = (match.benefits?['more'] as num?)?.toInt() ?? 0;
    final top = offers.map((o) => o.value).whereType<double>().fold<double?>(null, (a, b) => a == null || b > a ? b : a);
    final label = [
      askodoxChatLabel('offers', lang, count: offers.length + more),
      if (top != null) '${askodoxChatLabel('up_to', lang)} ${_money(top)}',
    ].join(' · ');
    return ActionChip(
      key: ValueKey('askodoxBenefits-${match.id}'),
      avatar: const Icon(Icons.local_offer_rounded, size: 16, color: Color(0xFF0F7B3F)),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      visualDensity: VisualDensity.compact,
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => AskodoxBenefitsSheet(match: match, lang: lang),
      ),
    );
  }
}

class AskodoxBenefitsSheet extends ConsumerStatefulWidget {
  const AskodoxBenefitsSheet({super.key, required this.match, required this.lang});

  final UniversalMatch match;
  final String lang;

  @override
  ConsumerState<AskodoxBenefitsSheet> createState() => _AskodoxBenefitsSheetState();
}

class _AskodoxBenefitsSheetState extends ConsumerState<AskodoxBenefitsSheet> {
  final _codes = <int, String>{};
  final _messages = <int, String>{};
  int? _busy;

  String _l(String key) => askodoxChatLabel(key, widget.lang);

  Future<void> _terms(AskodoxBenefit offer) async {
    await ref.read(askodoxBenefitsRepositoryProvider).open(offer.id);
    final url = Uri.tryParse(offer.sourceUrl ?? '');
    if (url != null && url.scheme == 'https') {
      try {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  Future<void> _claim(AskodoxBenefit offer) async {
    setState(() => _busy = offer.id);
    final result = await ref.read(askodoxBenefitsRepositoryProvider).claim(offer.id, orderValue: widget.match.price);
    if (!mounted) return;
    setState(() {
      _busy = null;
      if (result.ok && (result.code ?? '').isNotEmpty) {
        _codes[offer.id] = result.code!;
      } else if (result.ok) {
        _messages[offer.id] = _l('scratch_done');
      } else {
        _messages[offer.id] = _l(switch (result.error) {
          'sign_in' => 'sign_in_to_claim',
          'already_claimed' => 'already_claimed',
          _ => 'offer_unavailable',
        });
      }
    });
  }

  String _condition(Map<String, Object?> c) {
    final value = c['value'];
    return switch (c['type']) {
      'payment_method' => '${_l('pay_with')}: ${(value as List? ?? const []).join(', ')}',
      'min_purchase' => '${_l('min_purchase')}: ${_money((value as num).toDouble())}',
      'max_discount' => '${_l('up_to')} ${_money((value as num).toDouble())}',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final offers = AskodoxBenefit.listFrom(widget.match.benefits);
    final note = '${widget.match.benefits?['comparison_note'] ?? ''}';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.match.title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          for (final offer in offers)
            Card(
              key: ValueKey('askodoxBenefit-${offer.id}'),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([offer.provider, offer.name].where((s) => s.isNotEmpty).join(' · '),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(askodoxBenefitHeadline(offer, widget.lang),
                      style: const TextStyle(color: Color(0xFF0F7B3F), fontWeight: FontWeight.w800)),
                  for (final c in offer.conditions)
                    if (_condition(c).isNotEmpty) Text(_condition(c), style: const TextStyle(fontSize: 12)),
                  if (offer.expiresAt != null)
                    Text('${_l('expires')}: ${offer.expiresAt!.split('T').first}', style: const TextStyle(fontSize: 12)),
                  if (offer.verifiedAt != null)
                    Text('${_l('verified')}: ${offer.verifiedAt!.split('T').first}',
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  if (_codes[offer.id] != null)
                    Row(children: [
                      Text('${_l('your_code')}: '),
                      SelectableText(_codes[offer.id]!,
                          key: ValueKey('askodoxCouponCode-${offer.id}'),
                          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        onPressed: () => Clipboard.setData(ClipboardData(text: _codes[offer.id]!)),
                      ),
                    ]),
                  if (_messages[offer.id] != null)
                    Text(_messages[offer.id]!, key: ValueKey('askodoxBenefitMessage-${offer.id}')),
                  Wrap(spacing: 8, children: [
                    if ((offer.sourceUrl ?? '').isNotEmpty)
                      TextButton(
                        key: ValueKey('askodoxBenefitTerms-${offer.id}'),
                        onPressed: () => _terms(offer),
                        child: Text(_l('terms')),
                      ),
                    if (offer.claimable && _codes[offer.id] == null)
                      FilledButton.tonal(
                        key: ValueKey('askodoxBenefitClaim-${offer.id}'),
                        onPressed: _busy == offer.id ? null : () => _claim(offer),
                        child: Text(_l('get_coupon')),
                      ),
                  ]),
                ]),
              ),
            ),
          Text(note.isNotEmpty ? note : _l('offers_note'), style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        ]),
      ),
    );
  }
}

/// Scratch & Reveal: the reward was already decided by the server; the
/// scratching is only the reveal (nothing here can change the reward).
class AskodoxScratchCard extends StatefulWidget {
  const AskodoxScratchCard({super.key, required this.reward, required this.lang});

  final AskodoxClaimResult reward;
  final String lang;

  @override
  State<AskodoxScratchCard> createState() => _AskodoxScratchCardState();
}

class _AskodoxScratchCardState extends State<AskodoxScratchCard> {
  final _scratches = <Offset>[];
  bool _revealed = false;

  void _scratch(Offset point) {
    setState(() {
      _scratches.add(point);
      if (_scratches.length > 40) _revealed = true;
    });
  }

  String get _rewardText {
    final r = widget.reward;
    final lang = widget.lang;
    if (r.kind == 'gift' && (r.freeBenefit ?? '').isNotEmpty) {
      return '${askodoxChatLabel('gift', lang)} ${r.freeBenefit}';
    }
    final amount = r.value == null ? '' : '${_money(r.value!)} ';
    return '$amount${askodoxChatLabel(r.kind ?? 'reward', lang)}${r.code == null ? '' : '\n${r.code}'}';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        key: const Key('askodoxScratchCard'),
        title: Text(askodoxChatLabel('scratch_title', widget.lang)),
        content: SizedBox(
          width: 260,
          height: 150,
          child: GestureDetector(
            key: const Key('askodoxScratchArea'),
            onTap: () => setState(() => _revealed = true),
            onPanUpdate: (d) => _scratch(d.localPosition),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Stack(fit: StackFit.expand, children: [
                Container(
                  color: const Color(0xFFEFFAF3),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.all(12),
                  child: Text(_rewardText,
                      key: const Key('askodoxScratchReward'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF0F7B3F))),
                ),
                if (!_revealed)
                  CustomPaint(painter: _CoverPainter(_scratches), child: Center(
                    child: Text(askodoxChatLabel('scratch_hint', widget.lang),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  )),
              ]),
            ),
          ),
        ),
        actions: [
          if (_revealed)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(askodoxChatLabel('scratch_done', widget.lang)),
            ),
        ],
      );
}

class _CoverPainter extends CustomPainter {
  _CoverPainter(this.points);
  final List<Offset> points;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF6C4DFF));
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final p in points) {
      canvas.drawCircle(p, 18, clear);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CoverPainter oldDelegate) => true;
}
