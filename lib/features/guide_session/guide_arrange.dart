import '../money_home/launcher_layout.dart';
import '../money_home/money_home_pages.dart' show askodoxBuyerShippedLayout, askodoxSellerShippedLayout;
import '../money_home/money_home_store.dart';

/// Page arrangement after the guide session (owner 2026-11-28). The server names the pages the person's own words point
/// at (`/api/me/guide-session/arrangement`); this only MOVES them to the front of the screen the person already has:
/// - a page on its own is moved; a page inside a folder, hidden, or not on this screen is left alone;
/// - nothing is hidden, grouped or deleted, so [askodoxBringFirst] can always be undone by restoring the old layout;
/// - the order among the moved pages is the server's order (most matching words first).
AskodoxLaunchLayout askodoxBringFirst(AskodoxLaunchLayout base, List<String> ids) {
  var out = base;
  var at = 0;
  for (final id in ids) {
    if (out.indexOf(id) < 0) continue;
    out = out.move(id, at);
    at++;
  }
  return out;
}

/// The layouts a person had before the arrangement, so one tap can bring them back (null = the shipped screen).
class AskodoxGuideArrangeUndo {
  const AskodoxGuideArrangeUndo(this.saved);
  final List<({bool seller, bool side, String? shop, AskodoxLaunchLayout? before})> saved;

  Future<void> restore() async {
    for (final s in saved) {
      await askodoxSaveMoneyLayout(s.seller, s.before, shop: s.shop, side: s.side);
    }
  }
}

/// Applies the server's lists to the Buyer screen (Money and the side page) and, when a shop is in view, to that shop's
/// Seller screen. Returns null when nothing changed.
Future<AskodoxGuideArrangeUndo?> askodoxApplyGuideArrangement({
  required List<String> buyer,
  required List<String> seller,
  String? shop,
}) async {
  final saved = <({bool seller, bool side, String? shop, AskodoxLaunchLayout? before})>[];
  Future<void> one(bool isSeller, bool side, List<String> ids, String? shopId) async {
    if (ids.isEmpty || (isSeller && shopId == null)) return;
    final before = await askodoxLoadMoneyLayout(isSeller, shop: shopId, side: side);
    final base = before ?? (isSeller ? askodoxSellerShippedLayout() : askodoxBuyerShippedLayout());
    final next = askodoxBringFirst(base, ids);
    if (next.encode() == base.encode()) return;
    saved.add((seller: isSeller, side: side, shop: shopId, before: before));
    await askodoxSaveMoneyLayout(isSeller, next, shop: shopId, side: side);
  }

  for (final side in const [false, true]) {
    await one(false, side, buyer, null);
    await one(true, side, seller, shop);
  }
  return saved.isEmpty ? null : AskodoxGuideArrangeUndo(saved);
}
