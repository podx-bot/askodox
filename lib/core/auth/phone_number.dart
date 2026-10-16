/// Phone numbers in E.164 ("+919876543210") for sign-in.
///
/// India is the default country: a bare 10-digit mobile, "0" + 10 digits or
/// "91" + 10 digits all become +91XXXXXXXXXX. Anything typed with a leading
/// "+" (or "00") is kept as that international number. Returns null when the
/// input cannot be a real number (E.164 allows 8 to 15 digits after "+").
String? askodoxE164(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return null;
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  final international = raw.startsWith('+') || raw.startsWith('00');
  if (raw.startsWith('00')) digits = digits.substring(2);
  if (!international) {
    if (digits.length == 10 && RegExp(r'^[6-9]').hasMatch(digits)) return '+91$digits';
    if (digits.length == 11 && digits.startsWith('0')) return askodoxE164(digits.substring(1));
    if (digits.length == 12 && digits.startsWith('91')) return askodoxE164(digits.substring(2));
    return null;
  }
  if (digits.startsWith('91') && digits.length != 12) return null; // +91 needs exactly 10 more digits
  if (digits.startsWith('91') && !RegExp(r'^91[6-9]').hasMatch(digits)) return null;
  if (digits.length < 8 || digits.length > 15 || digits.startsWith('0')) return null;
  return '+$digits';
}

/// "+91 98765 43210" for display (other countries: "+<digits>").
String askodoxDisplayPhone(String e164) {
  final d = e164.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) return '+91 ${d.substring(2, 7)} ${d.substring(7)}';
  return '+$d';
}

/// Only the last four digits ("••••3210"): what logs and diagnostics may show.
String askodoxMaskedPhone(String value) {
  final d = value.replaceAll(RegExp(r'\D'), '');
  return d.length < 4 ? '••••' : '••••${d.substring(d.length - 4)}';
}
