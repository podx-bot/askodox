/// The business-name change rule as the app shows it (owner 2026-11-15): 15 days free after the name is first set,
/// then the next change locks the name for 30 days, the one after for 60 days, and every later one for 60 days.
/// The SERVER decides (backend name_change_policy.py); this only reads its `name_change` / `business_name_change`
/// answer so the box can say why it is locked before the person types.
class AskodoxNameChange {
  const AskodoxNameChange({
    required this.canChange,
    required this.freeWindow,
    this.freeUntil,
    this.nextAllowed,
    this.nextWaitDays = 30,
  });

  final bool canChange;
  final bool freeWindow;
  final DateTime? freeUntil;
  final DateTime? nextAllowed;
  final int nextWaitDays;

  static AskodoxNameChange? fromJson(Object? json) {
    if (json is! Map) return null;
    DateTime? when(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
    return AskodoxNameChange(
      canChange: json['can_change'] != false,
      freeWindow: json['free_window'] == true,
      freeUntil: when(json['free_until']),
      nextAllowed: when(json['next_allowed_at']),
      nextWaitDays: json['next_wait_days'] is num ? (json['next_wait_days'] as num).toInt() : 30,
    );
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String day(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  /// One short mixed Telugu / English sentence under the name box.
  String text(bool te) {
    if (!canChange) {
      final d = nextAllowed == null ? '' : day(nextAllowed!);
      return te
          ? 'ఇప్పుడు పేరు మార్చలేరు. $d తర్వాత మార్చవచ్చు.'
          : 'The name cannot be changed now. You can change it after $d.';
    }
    if (freeWindow) {
      final until = freeUntil == null ? null : day(freeUntil!);
      return te
          ? (until == null
              ? 'పేరు పెట్టాక 15 రోజులు ఉచితంగా మార్చుకోవచ్చు. ఆ తర్వాత మార్చితే $nextWaitDays రోజులు మళ్ళీ మార్చలేరు.'
              : 'ఈ పేరును $until వరకు ఉచితంగా మార్చుకోవచ్చు. ఆ తర్వాత మార్చితే $nextWaitDays రోజులు మళ్ళీ మార్చలేరు.')
          : (until == null
              ? 'Free to correct for 15 days after you set it. A change after that locks the name for $nextWaitDays days.'
              : 'Free to change until $until. A change after that locks the name for $nextWaitDays days.');
    }
    return te
        ? 'ఇప్పుడు మార్చవచ్చు. మార్చాక $nextWaitDays రోజులు మళ్ళీ మార్చలేరు.'
        : 'You can change it now. After a change it stays locked for $nextWaitDays days.';
  }
}
