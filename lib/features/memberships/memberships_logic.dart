/// Term memberships (owner 2026-11-27): the pure rules the screens share with the server (`pos_memberships.py`).
library;

/// The same day of the month [months] later; a day that month does not have becomes its last day
/// (31 Jan + 1 month = 28 / 29 Feb). Twin of the server's `add_months`.
DateTime askodoxTermEnd(DateTime start, int months) {
  final index = start.month - 1 + months;
  final year = start.year + index ~/ 12;
  final month = index % 12 + 1;
  final last = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, start.day > last ? last : start.day);
}

/// "2026-12-27" -> "27-12-2026"; anything else comes back as it is.
String askodoxDayText(Object? iso) {
  final text = '${iso ?? ''}';
  final parts = text.split('-');
  return parts.length == 3 && parts[0].length == 4 ? '${parts[2]}-${parts[1]}-${parts[0]}' : text;
}

String askodoxIsoDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

int askodoxTermInt(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

String askodoxTermRupees(Object? paise) {
  final value = askodoxTermInt(paise);
  return value % 100 == 0 ? '₹${value ~/ 100}' : '₹${(value / 100).toStringAsFixed(2)}';
}

/// Rupees typed in a box -> paise; 0 when it is not a positive amount.
int askodoxTermPaise(String typed) {
  final value = double.tryParse(typed.trim().replaceAll(',', ''));
  return value == null || value <= 0 ? 0 : (value * 100).round();
}

/// What the row says about a member's term.
String askodoxTermStateText(String state, int daysLeft, bool te) {
  switch (state) {
    case 'ending':
      if (daysLeft == 0) return te ? 'ఈ రోజు ముగుస్తుంది' : 'Ends today';
      return te ? '$daysLeft రోజుల్లో ముగుస్తుంది' : 'Ends in $daysLeft days';
    case 'ended':
      return te ? 'ముగిసింది · ఫీజు రావాలి' : 'Ended · fee to come';
    case 'left':
      return te ? 'వదిలి వెళ్ళారు' : 'Left';
    case 'stopped':
      return te ? 'ఆపారు' : 'Stopped';
    default:
      return te ? '$daysLeft రోజులు మిగిలాయి' : '$daysLeft days left';
  }
}

String askodoxTermMonthsText(int months, bool te) {
  if (months == 12) return te ? '1 సంవత్సరం' : '1 year';
  if (months == 1) return te ? '1 నెల' : '1 month';
  return te ? '$months నెలలు' : '$months months';
}
