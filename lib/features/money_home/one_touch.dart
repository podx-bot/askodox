import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/flags/askodox_release_phase.dart';
import '../../shared/widgets/header_menu.dart' show askodoxCareOpening;
import '../business/presentation/biz_hub.dart' show askodoxBizHubProvider;
import '../guide/in_app_guide.dart' show askodoxGuideSpeakerProvider;
import '../home/application/conversation_archive.dart' show AskodoxChatRequest, askodoxChatRequestProvider;
import '../pos/data/pos_repository.dart';

/// ONE TOUCH (owner 2026-11-25, design "ASKODOX ఒక్క టచ్ — కొను · అమ్ము"): the everyday jobs of each side on one strip
/// at the top of the కొను / అమ్ము page. A tap does the job or opens the ONE screen that finishes it; money always ends
/// on a confirm screen (reorder -> the order desk's total + Send), never paid by the strip itself.

// ------------------------------------------------------------------------------------------------ pure rules

/// Stages after which an order counts as finished (the person got it).
const askodoxFinishedOrderStages = {'served', 'handed', 'delivered', 'done'};

/// "Again the same" (మళ్ళీ అదే): the person's latest finished order, as the order-desk link that opens it with the same
/// items already in the cart (the desk asks only the last question and shows the total + Send). Dine-in comes back as
/// takeaway (no table now). Items the shop marked unavailable are left out; nothing left = null.
({String route, String shop, int items, int estimatePaise})? askodoxReorderOf(List<AskodoxJson> orders) {
  for (final o in orders) {
    if (!askodoxFinishedOrderStages.contains('${o['stage']}')) continue;
    final shop = '${o['business_id'] ?? ''}';
    if (shop.isEmpty) continue;
    final lines = <String>[];
    var estimate = 0;
    for (final i in (o['items'] as List? ?? const [])) {
      if (i is! Map || '${i['status']}' == 'unavailable') continue;
      final id = '${i['product_id'] ?? ''}';
      final qty = (i['qty'] as num?)?.toDouble() ?? 0;
      if (id.isEmpty || qty <= 0) continue;
      lines.add('$id:${qty == qty.roundToDouble() ? qty.toInt() : qty}');
      estimate += (((i['price_paise'] as num?) ?? 0) * qty).round();
    }
    if (lines.isEmpty) return null;
    final kind = '${o['kind']}' == 'delivery' ? 'delivery' : 'takeaway';
    final route = '/order-desk?code=${Uri.encodeQueryComponent(shop)}&kind=$kind'
        '&cart=${Uri.encodeQueryComponent(lines.join(','))}';
    return (route: route, shop: '${o['business_name'] ?? ''}', items: lines.length, estimatePaise: estimate);
  }
  return null;
}

/// What "today's count" says aloud (Seller): sales, dues, new orders -- short, numbers first.
String askodoxTodaySpoken(AskodoxJson hub, bool te) {
  int n(String key, String field) {
    final m = hub[key];
    return m is Map ? ((m[field] as num?)?.toInt() ?? 0) : 0;
  }

  String rupees(int paise) => '${(paise / 100).round()}'; // whole rupees: the voice never says ".00"
  final sales = n('sales', 'paise'), dues = n('dues', 'paise'), fresh = n('orders', 'new');
  final out = <String>[
    te ? 'ఈ రోజు అమ్మకం ${rupees(sales)} రూపాయలు.' : "Today's sales ${rupees(sales)} rupees.",
    if (dues > 0) te ? 'బాకీ ${rupees(dues)} రూపాయలు.' : 'Dues ${rupees(dues)} rupees.',
    if (fresh > 0) te ? 'కొత్త ఆర్డర్లు $fresh.' : '$fresh new orders.',
  ];
  return out.join(' ');
}

/// The next shop status for the one-touch switch: open <-> paused ("short break"); a closed shop opens.
String askodoxNextShopStatus(String status) => status == 'open' || status.isEmpty ? 'paused' : 'open';

// ------------------------------------------------------------------------------------------------ the strip

class _Touch {
  const _Touch(this.id, this.label, this.icon, this.color, this.onTap, {this.on});
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  /// A switch chip: true = green ON, false = grey OFF (null = a plain chip).
  final bool? on;
}

Widget _strip(List<_Touch> touches) => SizedBox(
      height: 58,
      child: ListView.separated(
        key: const Key('askodoxOneTouch'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        itemCount: touches.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final t = touches[i];
          final switchOn = t.on;
          final bg = switchOn == null ? Colors.white : (switchOn ? const Color(0xFF0B6B52) : const Color(0xFFE5E7EB));
          final fg = switchOn == true ? Colors.white : const Color(0xFF17201C);
          return Material(
            color: bg,
            elevation: switchOn == null ? 1 : 0,
            shadowColor: const Color(0x22000000),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              key: ValueKey(t.id), // the full key (registry + guide)
              borderRadius: BorderRadius.circular(16),
              onTap: t.onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 46),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(t.icon, size: 20, color: switchOn == true ? Colors.white : t.color),
                    const SizedBox(width: 6),
                    Text(t.label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: fg)),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
    );

void _ask(WidgetRef ref, BuildContext context, String text) {
  ref.read(askodoxChatRequestProvider.notifier).state = AskodoxChatRequest.ask(text);
  context.go('/');
}

final askodoxReorderProvider = FutureProvider.autoDispose((ref) async {
  try {
    return askodoxReorderOf(await ref.watch(askodoxPosRepositoryProvider).deskMine());
  } catch (_) {
    return null; // not signed in / offline: the strip simply has no reorder chip
  }
});

/// కొను page: again the same, need it now, compare price, report a problem.
class AskodoxBuyerOneTouch extends ConsumerWidget {
  const AskodoxBuyerOneTouch({super.key, required this.signedIn});
  final bool signedIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final again = signedIn ? ref.watch(askodoxReorderProvider).valueOrNull : null;
    return _strip([
      if (again != null)
        _Touch('askodoxOneTouch-again', te ? 'మళ్ళీ అదే · ${again.shop}' : 'Same again · ${again.shop}', Icons.replay_rounded,
            const Color(0xFF0B6B52), () => context.push(again.route)),
      _Touch('askodoxOneTouch-now', te ? 'ఇప్పుడే కావాలి' : 'Need it now', Icons.bolt_rounded, const Color(0xFFC2410C),
          () => _ask(ref, context, te ? 'దగ్గర్లో ఇప్పుడు తెరిచి ఉన్న షాప్‌లు చూపించు' : 'Show shops near me that are open now')),
      _Touch('askodoxOneTouch-compare', te ? 'ధర పోల్చు' : 'Compare price', Icons.bar_chart_rounded, const Color(0xFF2563EB),
          () => _ask(ref, context, te ? 'ఈ ఐటమ్ దగ్గర్లో ఎక్కడ తక్కువ ధరకు దొరుకుతుంది?' : 'Where nearby is this item cheapest?')),
      _Touch('askodoxOneTouch-problem', te ? 'సమస్య చెప్పు' : 'Report a problem', Icons.report_gmailerrorred_rounded,
          const Color(0xFFB42318), () => _ask(ref, context, askodoxCareOpening(te))),
    ]);
  }
}

/// అమ్ము page: shop open / break, hear today's count, out of stock, baaki reminders, flash offer, share the shop.
class AskodoxSellerOneTouch extends ConsumerStatefulWidget {
  const AskodoxSellerOneTouch({super.key, required this.shop});
  final AskodoxJson shop;

  @override
  ConsumerState<AskodoxSellerOneTouch> createState() => _AskodoxSellerOneTouchState();
}

class _AskodoxSellerOneTouchState extends ConsumerState<AskodoxSellerOneTouch> {
  String? _status; // set after this phone changed it (the shop list answers later)
  bool _busy = false;

  String get _id => '${widget.shop['id']}';

  Future<void> _toggle(bool te) async {
    if (_busy) return;
    final before = _status ?? '${widget.shop['status'] ?? 'open'}';
    final next = askodoxNextShopStatus(before);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(askodoxPosRepositoryProvider).setBusinessStatus(_id, next);
      if (!mounted) return;
      setState(() => _status = next);
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 4),
        content: Text(next == 'open'
            ? (te ? 'షాప్ ఓపెన్ — ఆర్డర్లు వస్తాయి' : 'Shop open — orders come in')
            : (te ? 'షాప్ బ్రేక్ — కొత్త ఆర్డర్లు రావు' : 'Shop on a break — no new orders')),
        action: SnackBarAction(label: te ? 'వెనక్కి' : 'Undo', onPressed: () => unawaited(_set(before))),
      ));
    } on AskodoxPosException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message(te))));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(te ? 'ఇంటర్నెట్ చూసి మళ్ళీ నొక్కండి' : 'Check the internet and tap again')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _set(String status) async {
    try {
      await ref.read(askodoxPosRepositoryProvider).setBusinessStatus(_id, status);
      if (mounted) setState(() => _status = status);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final owner = '${widget.shop['role']}' == 'owner';
    final status = _status ?? '${widget.shop['status'] ?? 'open'}';
    final hub = ref.watch(askodoxBizHubProvider(_id)).valueOrNull?.$2;
    final perms = {for (final p in (widget.shop['permissions'] as List? ?? const [])) '$p'};
    bool may(String perm) => owner || perms.contains(perm);
    void go(String route) => context.push(route);
    final touches = <_Touch>[
      if (owner)
        _Touch('askodoxOneTouch-open', status == 'open' ? (te ? 'షాప్ ఓపెన్' : 'Shop open') : (te ? 'షాప్ బ్రేక్' : 'On a break'),
            status == 'open' ? Icons.storefront_rounded : Icons.pause_circle_rounded, const Color(0xFF0B6B52),
            () => unawaited(_toggle(te)),
            on: status == 'open'),
      if (hub != null && may('reports'))
        _Touch('askodoxOneTouch-today', te ? 'ఈ రోజు లెక్క వినండి' : 'Hear today', Icons.volume_up_rounded, const Color(0xFF0D9488),
            () => unawaited(ref.read(askodoxGuideSpeakerProvider)(askodoxTodaySpoken(hub, te), te ? 'te' : 'en'))),
      if (may('products') || may('stock'))
        _Touch('askodoxOneTouch-stock', te ? 'స్టాక్ లేదు' : 'Out of stock', Icons.remove_shopping_cart_rounded, const Color(0xFFB42318),
            () => go('/desk/$_id/menu')),
      if (may('collect') || may('customers'))
        _Touch('askodoxOneTouch-dues', te ? 'బాకీ గుర్తు' : 'Baaki reminders', Icons.notifications_active_rounded, const Color(0xFFB45309),
            () => go('/pos/$_id/dues')),
      if (owner)
        _Touch('askodoxOneTouch-offer', te ? 'ఫ్లాష్ ఆఫర్' : 'Flash offer', Icons.local_offer_rounded, const Color(0xFFC2410C),
            () => go('/notices/new')),
      if (owner)
        _Touch('askodoxOneTouch-share', te ? 'షాప్ షేర్' : 'Share shop', Icons.share_rounded, const Color(0xFF2563EB), () => go('/pos/$_id/link')),
    ];
    final shown = [
      for (final t in touches)
        if (t.id == 'askodoxOneTouch-open' || t.id == 'askodoxOneTouch-today' || askodoxRouteShownNow(_routeOf(t.id))) t,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    return _strip(shown);
  }

  String _routeOf(String id) => switch (id) {
        'askodoxOneTouch-stock' => '/desk/$_id/menu',
        'askodoxOneTouch-dues' => '/pos/$_id/dues',
        'askodoxOneTouch-offer' => '/notices/new',
        'askodoxOneTouch-share' => '/pos/$_id/link',
        _ => '/',
      };
}
