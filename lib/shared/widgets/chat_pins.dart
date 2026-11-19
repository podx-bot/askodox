import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/pos/data/pos_repository.dart';

/// Chat shortcut strip (owner 2026-11-19): at most THREE buttons the person pinned themselves, shown just above the
/// chat box. Long-press a tile / row anywhere -> "Pin above the chat". A pin is a LINK to the same page (never a copy
/// of the button); a 4th pin asks which one to replace. The strip folds to a thin handle and opens again on a tap.
const askodoxChatPinsKey = 'askodox.chat.pins.v1';
const askodoxChatPinsFoldedKey = 'askodox.chat.pins.folded.v1';
const askodoxChatPinsMax = 5; // owner 2026-11-19: five (was three)

class AskodoxChatPin {
  const AskodoxChatPin({required this.id, required this.route, required this.en, required this.te});

  /// The tile's fixed key id (never its shown name), so a renamed tile stays the same pin.
  final String id;
  final String route;
  final String en;
  final String te;

  String label(bool telugu) => telugu && te.isNotEmpty ? te : en;

  Map<String, Object?> toJson() => {'id': id, 'route': route, 'en': en, 'te': te};

  static AskodoxChatPin? fromJson(Object? v) {
    if (v is! Map) return null;
    final id = '${v['id'] ?? ''}';
    final route = '${v['route'] ?? ''}';
    if (id.isEmpty || !route.startsWith('/')) return null;
    return AskodoxChatPin(id: id, route: route, en: '${v['en'] ?? ''}', te: '${v['te'] ?? ''}');
  }
}

class AskodoxChatPinsState {
  const AskodoxChatPinsState({this.pins = const [], this.folded = false});
  final List<AskodoxChatPin> pins;
  final bool folded;
}

class AskodoxChatPinsController extends StateNotifier<AskodoxChatPinsState> {
  AskodoxChatPinsController() : super(const AskodoxChatPinsState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(askodoxChatPinsKey);
      final list = raw == null ? const [] : (jsonDecode(raw) as List? ?? const []);
      if (!mounted) return;
      state = AskodoxChatPinsState(
        pins: [for (final v in list) AskodoxChatPin.fromJson(v)].whereType<AskodoxChatPin>().take(askodoxChatPinsMax).toList(),
        folded: prefs.getBool(askodoxChatPinsFoldedKey) ?? false,
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(askodoxChatPinsKey, jsonEncode([for (final p in state.pins) p.toJson()]));
      await prefs.setBool(askodoxChatPinsFoldedKey, state.folded);
    } catch (_) {}
  }

  bool isPinned(String id) => state.pins.any((p) => p.id == id);

  /// Adds [pin]; with three already, [replace] names the one it takes the place of.
  void pin(AskodoxChatPin pin, {String? replace}) {
    final list = [for (final p in state.pins) if (p.id != pin.id && p.id != replace) p];
    if (list.length >= askodoxChatPinsMax) return;
    state = AskodoxChatPinsState(pins: [...list, pin], folded: false);
    _save();
  }

  void unpin(String id) {
    state = AskodoxChatPinsState(pins: [for (final p in state.pins) if (p.id != id) p], folded: state.folded);
    _save();
  }

  /// Moves a pin one place earlier (-1) or later (+1) in the strip.
  void move(String id, int delta) {
    final list = [...state.pins];
    final at = list.indexWhere((p) => p.id == id);
    final to = at + delta;
    if (at < 0 || to < 0 || to >= list.length) return;
    final pin = list.removeAt(at);
    list.insert(to, pin);
    state = AskodoxChatPinsState(pins: list, folded: state.folded);
    _save();
  }

  void setFolded(bool folded) {
    state = AskodoxChatPinsState(pins: state.pins, folded: folded);
    _save();
  }
}

final askodoxChatPinsProvider =
    StateNotifierProvider<AskodoxChatPinsController, AskodoxChatPinsState>((ref) => AskodoxChatPinsController());

bool _te(BuildContext context) => Localizations.localeOf(context).languageCode == 'te';

/// Long-press on a tile / row: pin it above the chat (or take it off). Three already -> choose one to replace.
Future<void> askodoxOfferChatPin(BuildContext context, AskodoxChatPin pin) async {
  final container = ProviderScope.containerOf(context);
  final pins = container.read(askodoxChatPinsProvider.notifier);
  final te = _te(context);
  final pinned = pins.isPinned(pin.id);
  final current = container.read(askodoxChatPinsProvider).pins;
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(pin.label(te), style: const TextStyle(fontWeight: FontWeight.w800))),
        if (pinned && current.indexWhere((p) => p.id == pin.id) > 0)
          ListTile(
            key: const Key('askodoxChatPinEarlier'),
            leading: const Icon(Icons.arrow_back_rounded),
            title: Text(te ? 'ముందుకు జరుపు' : 'Move earlier'),
            onTap: () => Navigator.pop(sheet, 'earlier'),
          ),
        if (pinned && current.indexWhere((p) => p.id == pin.id) < current.length - 1)
          ListTile(
            key: const Key('askodoxChatPinLater'),
            leading: const Icon(Icons.arrow_forward_rounded),
            title: Text(te ? 'వెనక్కి జరుపు' : 'Move later'),
            onTap: () => Navigator.pop(sheet, 'later'),
          ),
        if (pinned)
          ListTile(
            key: const Key('askodoxChatPinRemove'),
            leading: const Icon(Icons.push_pin_outlined),
            title: Text(te ? 'చాట్ పైనుంచి తీసేయి' : 'Remove from above the chat'),
            onTap: () => Navigator.pop(sheet, 'remove'),
          )
        else if (current.length < askodoxChatPinsMax)
          ListTile(
            key: const Key('askodoxChatPinAdd'),
            leading: const Icon(Icons.push_pin),
            title: Text(te ? 'చాట్ పైన పిన్ చేయి' : 'Pin above the chat'),
            subtitle: Text(te ? 'గరిష్టంగా $askodoxChatPinsMax' : 'Up to $askodoxChatPinsMax'),
            onTap: () => Navigator.pop(sheet, 'add'),
          )
        else ...[
          ListTile(
              title: Text(te ? '$askodoxChatPinsMax పిన్‌లు ఉన్నాయి — దేని బదులు పెట్టాలి?' : '$askodoxChatPinsMax pins already — replace which one?')),
          for (final p in current)
            ListTile(
              key: ValueKey('askodoxChatPinReplace-${p.id}'),
              leading: const Icon(Icons.swap_horiz),
              title: Text(p.label(te)),
              onTap: () => Navigator.pop(sheet, 'replace:${p.id}'),
            ),
        ],
      ]),
    ),
  );
  if (choice == null) return;
  if (choice == 'earlier' || choice == 'later') {
    pins.move(pin.id, choice == 'earlier' ? -1 : 1);
  } else if (choice == 'remove') {
    pins.unpin(pin.id);
  } else if (choice == 'add') {
    pins.pin(pin);
  } else if (choice.startsWith('replace:')) {
    pins.pin(pin, replace: choice.substring(8));
  }
}

/// ON in the real app (main.dart): the person's RUNNING shop orders show as an automatic chip in the strip.
/// Widget tests keep it off (no surprise API call).
bool askodoxLiveOrderChip = false;

/// Owner 2026-11-19: once a table / parcel / delivery order is placed, a shortcut to it sits above the chat by itself
/// ("ask for water, a spoon, the bill ...") until the order is finished, then goes away. Not one of the five pins.
class AskodoxLiveOrdersController extends StateNotifier<List<AskodoxJson>> {
  AskodoxLiveOrdersController(this._ref) : super(const []) {
    refresh();
  }
  final Ref _ref;
  static const _closed = {'done', 'rejected', 'cancelled'};

  Future<void> refresh() async {
    if (!askodoxLiveOrderChip) return;
    try {
      final repo = _ref.read(askodoxPosRepositoryProvider);
      final orders = await repo.deskMine();
      var reserved = const <AskodoxJson>[];
      try {
        reserved = await repo.myReservations();
      } catch (_) {
        // an older server: orders only
      }
      // A shop person: the running orders of their own shop(s), one chip per shop, while any is running.
      final shopChips = <AskodoxJson>[];
      try {
        for (final shop in (await repo.businesses()).take(3)) {
          final running = askodoxPosList((await repo.deskOrders('${shop['id']}'))['orders']);
          if (running.isNotEmpty) {
            shopChips.add({'shop_orders': true, 'id': 'shop-${shop['id']}', 'business_id': shop['id'], 'count': running.length});
          }
        }
      } catch (_) {
        // not a shop person, or no permission for the orders desk: no chip
      }
      if (mounted) {
        state = [
          ...shopChips,
          for (final r in reserved) if ('${r['status']}' == 'booked') {...r, 'reservation': true},
          for (final o in orders) if (!_closed.contains('${o['stage']}')) o,
        ];
      }
    } catch (_) {
      // signed out / offline: no chip
    }
  }
}

final askodoxLiveOrdersProvider =
    StateNotifierProvider<AskodoxLiveOrdersController, List<AskodoxJson>>((ref) => AskodoxLiveOrdersController(ref));

/// A reserved table: where, when, and one button to cancel it.
Future<void> _showReservation(BuildContext context, WidgetRef ref, AskodoxJson r, bool te) async {
  final at = DateTime.tryParse('${r['at']}')?.toLocal();
  final when = at == null ? '' : '${at.day}/${at.month} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
  final cancel = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.event_seat_outlined),
          title: Text('${r['shop']} · ${r['table_name']}', style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text('$when · ${r['people']} ${te ? 'మంది' : 'people'}'),
        ),
        ListTile(
          key: const Key('askodoxReservationCancel'),
          leading: const Icon(Icons.close_rounded, color: Color(0xFFB42318)),
          title: Text(te ? 'రిజర్వేషన్ రద్దు చేయి' : 'Cancel this reservation'),
          onTap: () => Navigator.pop(sheet, true),
        ),
      ]),
    ),
  );
  if (cancel != true) return;
  try {
    await ref.read(askodoxPosRepositoryProvider).cancelMyReservation('${r['id']}');
  } catch (_) {
    // the refresh after this shows the real state
  }
}

/// The strip above the chat box: the person's pins (a tap opens the page; long-press offers removal) and an arrow
/// that folds it to a thin handle. Nothing is drawn when nothing is pinned.
class AskodoxChatPinStrip extends ConsumerWidget {
  const AskodoxChatPinStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(askodoxChatPinsProvider);
    final live = askodoxLiveOrderChip ? ref.watch(askodoxLiveOrdersProvider) : const <AskodoxJson>[];
    if (state.pins.isEmpty && live.isEmpty) return const SizedBox.shrink();
    final te = _te(context);
    final control = ref.read(askodoxChatPinsProvider.notifier);
    if (state.folded && live.isEmpty) {
      return Center(
        child: InkWell(
          key: const Key('askodoxChatPinsOpen'),
          borderRadius: BorderRadius.circular(10),
          onTap: () => control.setFolded(false),
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Container(
                width: 42, height: 4, decoration: BoxDecoration(color: const Color(0xFFB8C0CC), borderRadius: BorderRadius.circular(4))),
          ),
        ),
      );
    }
    return Padding(
      key: const Key('askodoxChatPins'),
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final o in live)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    key: ValueKey('askodoxLiveOrder-${o['id']}'),
                    backgroundColor: const Color(0xFFE8F5EC),
                    avatar: Icon('${o['kind']}' == 'dine_in' ? Icons.table_restaurant_outlined : Icons.receipt_long_outlined,
                        size: 16, color: const Color(0xFF17784C)),
                    label: Text(
                        o['shop_orders'] == true
                            ? (te ? 'నడుస్తున్న ఆర్డర్లు (${o['count']})' : 'Running orders (${o['count']})')
                            : o['reservation'] == true
                            ? '${o['table_name']} · ${te ? 'రిజర్వ్' : 'Reserved'}'
                            : '${o['table_name'] ?? o['business_name'] ?? ''} · ${'${o['kind']}' == 'dine_in' ? (te ? 'అడగండి' : 'Ask') : (te ? 'ఆర్డర్' : 'Order')}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () async {
                      if (o['shop_orders'] == true) {
                        await context.push('/desk/${o['business_id']}');
                      } else if (o['reservation'] == true) {
                        await _showReservation(context, ref, o, te);
                      } else {
                        await context.push('/order-desk/track/${o['id']}');
                      }
                      await ref.read(askodoxLiveOrdersProvider.notifier).refresh();
                    },
                  ),
                ),
              for (final p in state.folded ? const <AskodoxChatPin>[] : state.pins)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onLongPress: () => askodoxOfferChatPin(context, p),
                    child: ActionChip(
                      key: ValueKey('askodoxChatPin-${p.id}'),
                      avatar: const Icon(Icons.push_pin, size: 16),
                      label: Text(p.label(te), style: const TextStyle(fontWeight: FontWeight.w700)),
                      onPressed: () => context.push(p.route),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        IconButton(
          key: const Key('askodoxChatPinsFold'),
          tooltip: te ? 'దాచు' : 'Hide',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: () => control.setFolded(true),
        ),
      ]),
    );
  }
}
