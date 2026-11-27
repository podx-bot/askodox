import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'yield_math.dart';

/// The yield books of the person's shops, on this phone only for now (account-scoped, see
/// `askodoxAccountScopedKeys`). The last [askodoxYieldKeep] lots and day closes of a shop are kept.
const askodoxYieldPrefsKey = 'askodox.yield.v1';
const askodoxYieldKeep = 400;
const askodoxYieldMaxRows = 12;

final askodoxYieldClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class AskodoxYieldState {
  const AskodoxYieldState({this.loaded = false, this.books = const {}});
  final bool loaded;
  final Map<String, AskodoxYieldBook> books;

  AskodoxYieldBook book(String shop) => books[shop] ?? const AskodoxYieldBook();
}

class AskodoxYieldController extends StateNotifier<AskodoxYieldState> {
  AskodoxYieldController() : super(const AskodoxYieldState()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) state = AskodoxYieldState(loaded: true, books: askodoxYieldDecode(prefs.getString(askodoxYieldPrefsKey)));
    } catch (_) {
      if (mounted) state = const AskodoxYieldState(loaded: true);
    }
  }

  Future<void> _put(String shop, AskodoxYieldBook book) async {
    state = AskodoxYieldState(loaded: true, books: {...state.books, shop: book});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(askodoxYieldPrefsKey, askodoxYieldEncode(state.books));
    } catch (_) {
      // Stays on screen; saved with the next change.
    }
  }

  List<T> _kept<T>(List<T> rows) => rows.length > askodoxYieldKeep ? rows.sublist(rows.length - askodoxYieldKeep) : rows;

  /// A new lot, or the same lot again with its later numbers (same id).
  Future<void> saveBatch(String shop, AskodoxYieldBatch batch) async {
    final book = state.book(shop);
    final rest = [for (final b in book.batches) if (b.id != batch.id) b];
    await _put(shop, book.copyWith(batches: _kept([...rest, batch])));
  }

  Future<void> saveDay(String shop, AskodoxYieldDay day) async {
    final book = state.book(shop);
    final rest = [for (final d in book.days) if (d.item != day.item || d.day != day.day) d];
    await _put(shop, book.copyWith(days: _kept([...rest, day])));
  }

  Future<void> setMinProfit(String shop, String item, int paise) async {
    final book = state.book(shop);
    await _put(shop, book.copyWith(minProfit: {...book.minProfit, item: paise < 0 ? 0 : paise}));
  }

  /// A further form of an item (same name = the same form with its newer numbers); at most [askodoxYieldMaxRows].
  Future<void> saveForm(String shop, String item, AskodoxYieldForm form) async {
    final book = state.book(shop);
    final rest = [for (final f in book.formsOf(item)) if (f.name != form.name) f];
    if (form.name.trim().isEmpty || rest.length >= askodoxYieldMaxRows) return;
    await _put(shop, book.copyWith(forms: {...book.forms, item: [...rest, form]}));
  }

  Future<void> removeForm(String shop, String item, String name) async {
    final book = state.book(shop);
    await _put(shop, book.copyWith(forms: {...book.forms, item: [for (final f in book.formsOf(item)) if (f.name != name) f]}));
  }

  /// A line of the measure card (same name = the same line with its newer numbers).
  Future<void> savePortion(String shop, String item, AskodoxYieldPortion portion) async {
    final book = state.book(shop);
    final rest = [for (final p in book.portionsOf(item)) if (p.name != portion.name) p];
    if (portion.name.trim().isEmpty || rest.length >= askodoxYieldMaxRows) return;
    await _put(shop, book.copyWith(portions: {...book.portions, item: [...rest, portion]}));
  }

  Future<void> removePortion(String shop, String item, String name) async {
    final book = state.book(shop);
    await _put(shop,
        book.copyWith(portions: {...book.portions, item: [for (final p in book.portionsOf(item)) if (p.name != name) p]}));
  }
}

final askodoxYieldProvider =
    StateNotifierProvider<AskodoxYieldController, AskodoxYieldState>((ref) => AskodoxYieldController());
