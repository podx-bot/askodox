// The 3-step pages (owner 2026-11-22: "every second page in 3 pieces, done in just 3 steps, understood at a glance").
// Pure rules shared by the bill / dues / check-in / day-close steps, kept here so they are tested without a screen.

import 'dart:math' as math;

import '../../pos/domain/pos_money.dart';

/// One key on the big number pad: digits, "00" and "del". The value is whole rupees as typed ("2350"); a leading
/// zero is dropped and at most [maxDigits] digits are kept (₹99,99,999 by default).
String askodoxKeypadPress(String current, String key, {int maxDigits = 7}) {
  if (key == 'del') return current.isEmpty ? '' : current.substring(0, current.length - 1);
  if (!RegExp(r'^\d+$').hasMatch(key)) return current;
  var next = current + key;
  next = next.replaceFirst(RegExp(r'^0+'), '');
  if (next.length > maxDigits) return current;
  return next;
}

/// Typed rupees ("2350") -> paise (235000); empty -> 0.
int askodoxKeypadPaise(String typed) => typed.isEmpty ? 0 : (int.tryParse(typed) ?? 0) * 100;

/// Units sold by weight / volume: a tap adds half a unit after the first whole one.
bool askodoxWeighable(String unit) => const {'kg', 'l', 'litre', 'liter'}.contains(unit.toLowerCase());

/// The next quantity (milli-units of the item's own unit) after one tap on an item tile:
/// kg / litre -> 1, 1½, 2, 2½ ...; grams / ml -> 250 at a time; everything else -> one more piece / plate.
int askodoxBillTapQty(int currentMilli, String unit) {
  final u = unit.toLowerCase();
  if (askodoxWeighable(u)) return currentMilli <= 0 ? 1000 : currentMilli + 500;
  if (u == 'g' || u == 'gm' || u == 'ml') return currentMilli + 250000;
  return currentMilli + 1000;
}

/// Price of one line: price per unit x quantity (milli-units), rounded to the paisa.
int askodoxLinePaise(int pricePaise, int qtyMilli) => (pricePaise * qtyMilli / 1000).round();

/// A quantity as the small badge on a tile shows it: 1000 -> "1", 1500 -> "1½", 250 -> "¼", 12000 -> "12",
/// 1200 -> "1.2". Grams / ml are whole numbers already (250000 -> "250").
String askodoxQtyShort(int milli) {
  if (milli <= 0) return '';
  final whole = milli ~/ 1000;
  final rest = milli % 1000;
  if (rest == 0) return '$whole';
  const marks = {250: '¼', 500: '½', 750: '¾'};
  final mark = marks[rest];
  if (mark != null) return whole == 0 ? mark : '$whole$mark';
  var text = (milli / 1000).toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return text;
}

/// Money received from one person against their dues: oldest bill first, each bill gets at most what it still owes.
/// [bills] = (bill id, due paise) oldest first; returns (bill id, paise to settle) for every bill that gets money.
List<(String, int)> askodoxSplitDuePayment(List<(String, int)> bills, int amountPaise) {
  final out = <(String, int)>[];
  var left = amountPaise;
  for (final (id, due) in bills) {
    if (left <= 0) break;
    if (due <= 0) continue;
    final take = left < due ? left : due;
    out.add((id, take));
    left -= take;
  }
  return out;
}

/// How the customer paid, when it was said together with the items ("12 number 2, UPI"): cash / online / due;
/// null when the words name no way of paying. The step page only PRE-SELECTS it -- the cashier still taps it.
String? askodoxSpokenPayMethod(String words) {
  final s = ' ${words.toLowerCase()} ';
  bool any(List<String> marks) => marks.any(s.contains);
  if (any(const ['బాకీ', 'baaki', 'baki', 'udhar', 'udhaar', 'credit', 'అప్పు', 'తర్వాత కడ', 'later'])) return 'due';
  if (any(const ['upi', 'యూపీఐ', 'యుపిఐ', 'online', 'ఆన్‌లైన్', 'ఆన్లైన్', 'phonepe', 'phone pe', 'ఫోన్ పే', 'ఫోన్‌పే', 'gpay',
    'google pay', 'గూగుల్ పే', 'paytm', 'పేటీఎం', 'scan', 'స్కాన్', ' qr '])) {
    return 'online';
  }
  if (any(const ['cash', 'క్యాష్', 'నగదు', 'కాష్'])) return 'cash';
  return null;
}

/// The first amount in spoken / typed words ("2,350 ఇచ్చారు" -> 235000 paise); null when there is none.
int? askodoxSpokenRupees(String words) {
  final match = RegExp(r'\d[\d,]*(?:\.\d{1,2})?').firstMatch(words);
  if (match == null) return null;
  return askodoxParsePaise(match.group(0)!.replaceAll(',', ''));
}

/// Rupees for the big number on a step page: 1845000 paise -> "₹18,450" (paise only when there are some).
String askodoxStepRupees(int paise) {
  final text = askodoxPaise(paise);
  return text.endsWith('.00') ? text.substring(0, text.length - 3) : text;
}

/// A person's 10-digit mobile number from typed / pasted text ("+91 98xxx xxxxx" -> 10 digits); '' when not one.
String askodoxTenDigits(String text) {
  var digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length == 12 && digits.startsWith('91')) digits = digits.substring(2);
  if (digits.length == 11 && digits.startsWith('0')) digits = digits.substring(1);
  return RegExp(r'^[6-9]\d{9}$').hasMatch(digits) ? digits : '';
}

/// "1.5" / "1½" / "2" typed in the quantity box -> milli-units; null when it is not a quantity.
int? askodoxParseQtyMilli(String text) {
  final t = text.trim().replaceAll('½', '.5').replaceAll('¼', '.25').replaceAll('¾', '.75').replaceAll(',', '.');
  if (t.isEmpty) return null;
  final v = double.tryParse(t.startsWith('.') ? '0$t' : t);
  if (v == null || v < 0) return null;
  return (v * 1000).round();
}

/// One calculator-bill row: quantity x rate (rupees, decimals allowed) in paise. 0 when either is not a number > 0.
int askodoxCalcRowPaise(String qty, String rate) {
  final q = askodoxParseQtyMilli(qty);
  final r = askodoxCalcRatePaise(rate);
  if (q == null || q <= 0 || r <= 0) return 0;
  return askodoxLinePaise(r, q);
}

/// A typed rate in rupees ("12", "12.50", "1,200") in paise; 0 when it is not a number.
int askodoxCalcRatePaise(String rate) => askodoxParsePaise(rate.trim().replaceAll(',', '')) ?? 0;

/// Metres between two places (the server measures the same way): "you are 40 m from the shop" is shown BEFORE the face
/// check, so nobody does the face part only to be refused for the distance (owner 2026-11-23).
int askodoxDistanceM(double aLat, double aLng, double bLat, double bLng) {
  const r = 6371000.0;
  final p1 = aLat * math.pi / 180, p2 = bLat * math.pi / 180;
  final dp = (bLat - aLat) * math.pi / 180, dl = (bLng - aLng) * math.pi / 180;
  final h = math.sin(dp / 2) * math.sin(dp / 2) + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return (2 * r * math.asin(math.sqrt(h))).floor();
}

/// "40 m" / "2.3 km".
String askodoxDistanceText(int metres) => metres < 1000 ? '$metres m' : '${(metres / 1000).toStringAsFixed(1)} km';

