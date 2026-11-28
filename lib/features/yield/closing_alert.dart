import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/theme/askodox_look.dart';
import '../home/domain/shopping_mode.dart';
import '../money_home/money_home_store.dart';
import '../pos/data/pos_repository.dart';
import 'yield_math.dart';
import 'yield_store.dart';

/// Closing time (owner 2026-11-27, design "closing alert"): the owner sets his own closing time; after it, until
/// midnight, a chip above the Home chat says which item's stock has not been closed today. It opens the day end on
/// the yield page. It never sends anything and never opens by itself (no scheduled push is built: that needs a
/// native change). Phone only, per shop.
const askodoxClosingPrefsKey = 'askodox.closing.v1';

/// Switched on only in `main()`.
bool askodoxClosingChip = false;

/// `HH:MM` kept as typed by the time picker; null when it is not a clock time.
({int hour, int minute})? askodoxClosingParse(String text) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
  if (h > 23 || mi > 59) return null;
  return (hour: h, minute: mi);
}

String askodoxClosingText(int hour, int minute) => '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

String _dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Items whose stock is still to be closed today: the closing time has passed, the item had a lot in the last
/// three days (so it is one the owner really trades), and no day end of it is saved for today.
List<String> askodoxClosingDue(AskodoxYieldBook book, DateTime now, String closing) {
  final t = askodoxClosingParse(closing);
  if (t == null) return const [];
  if (now.hour * 60 + now.minute < t.hour * 60 + t.minute) return const [];
  final today = _dayKey(now);
  final since = _dayKey(DateTime(now.year, now.month, now.day).subtract(const Duration(days: 3)));
  final closed = {for (final d in book.days) if (d.day == today) d.item};
  final names = <String>[];
  for (final b in book.batches) {
    if (b.day.compareTo(since) >= 0 && !closed.contains(b.item) && !names.contains(b.item)) names.add(b.item);
  }
  return names;
}

class AskodoxClosingController extends StateNotifier<Map<String, String>> {
  AskodoxClosingController() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(askodoxClosingPrefsKey) ?? '';
      final out = <String, String>{};
      for (final part in raw.split('|')) {
        final i = part.lastIndexOf('=');
        if (i > 0 && askodoxClosingParse(part.substring(i + 1)) != null) out[part.substring(0, i)] = part.substring(i + 1);
      }
      if (mounted) state = out;
    } catch (_) {}
  }

  /// The server only learns the clock time, so it can push at that time. Best effort: the chip works without it.
  Future<void> Function(String shop, String? time) tell = (shop, time) async {};

  Future<void> set(String shop, String? time) async {
    final next = {...state};
    if (time == null || askodoxClosingParse(time) == null) {
      next.remove(shop);
    } else {
      next[shop] = time;
    }
    state = next;
    try {
      await tell(shop, next[shop]);
    } catch (_) {}
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(askodoxClosingPrefsKey, [for (final e in next.entries) '${e.key}=${e.value}'].join('|'));
    } catch (_) {}
  }
}

final askodoxClosingProvider = StateNotifierProvider<AskodoxClosingController, Map<String, String>>((ref) {
  final c = AskodoxClosingController();
  c.tell = (shop, time) => ref.read(askodoxPosRepositoryProvider).setClosingTime(shop, time);
  return c;
});
final askodoxClosingClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The closing-time row on the yield page: the owner's own time, or off.
class AskodoxClosingRow extends ConsumerWidget {
  const AskodoxClosingRow({super.key, required this.businessId});
  final String businessId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final te = Localizations.localeOf(context).languageCode == 'te';
    final time = ref.watch(askodoxClosingProvider)[businessId];
    return ListTile(
      key: const Key('askodoxYieldClosing'),
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.alarm_outlined),
      title: Text(te ? 'క్లోజింగ్ టైమ్ (స్టాక్ గుర్తు చేస్తుంది)' : 'Closing time (reminds you to close stock)'),
      subtitle: Text(time ?? (te ? 'పెట్టలేదు' : 'Not set')),
      trailing: time == null
          ? null
          : IconButton(
              key: const Key('askodoxYieldClosingOff'),
              icon: const Icon(Icons.close),
              onPressed: () => ref.read(askodoxClosingProvider.notifier).set(businessId, null)),
      onTap: () async {
        final cur = time == null ? null : askodoxClosingParse(time);
        final picked = await showTimePicker(
            context: context, initialTime: TimeOfDay(hour: cur?.hour ?? 22, minute: cur?.minute ?? 30));
        if (picked != null) await ref.read(askodoxClosingProvider.notifier).set(businessId, askodoxClosingText(picked.hour, picked.minute));
      },
    );
  }
}

/// Above the Home chat on the Seller side, after the owner's closing time, while an item's stock is not closed.
class AskodoxClosingChipStrip extends ConsumerWidget {
  const AskodoxClosingChipStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!askodoxClosingChip || !ref.watch(askodoxSellerModeProvider)) return const SizedBox.shrink();
    final picked = askodoxPickShop(ref.watch(askodoxMyShopsProvider).valueOrNull ?? const [], ref.watch(askodoxMoneyShopProvider));
    if (picked == null) return const SizedBox.shrink();
    final shop = '${picked['id']}';
    final closing = ref.watch(askodoxClosingProvider)[shop];
    final yieldState = ref.watch(askodoxYieldProvider);
    if (closing == null || !yieldState.loaded) return const SizedBox.shrink();
    final due = askodoxClosingDue(yieldState.book(shop), ref.watch(askodoxClosingClockProvider)(), closing);
    if (due.isEmpty) return const SizedBox.shrink();
    final te = Localizations.localeOf(context).languageCode == 'te';
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: ActionChip(
          key: const Key('askodoxClosingChip'),
          avatar: const Icon(Icons.alarm_outlined, size: 16, color: AskodoxLook.accentText),
          label: Text(te ? 'క్లోజింగ్ స్టాక్ చూడండి · ${askodoxYieldItemName(due.first, te)}' : 'Close the stock · ${askodoxYieldItemName(due.first, te)}',
              overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          onPressed: () => context.push('/pos/$shop/yield'),
        ),
      ),
    );
  }
}
