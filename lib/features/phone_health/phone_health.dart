/// Phone health (owner 2026-11-26): the app checks ONLY ITS OWN settings on this phone and tells the person, in plain
/// words and for THEIR phone maker, which page to open and what to switch. Pure rules: no Flutter, no phone calls.
///
/// It never reads other apps, messages or photos, and it never taps a setting for the person (no Accessibility
/// automation: a Google Play rule). A report goes to ASKODOX only when the person presses "పంపు", every time.
library;

/// One thing the app can see about itself. [id] is one of the server's fixed check ids.
class AskodoxPhoneCheck {
  const AskodoxPhoneCheck(this.id, this.state, {this.fix = ''});
  final String id;

  /// ok | bad | unknown ("unknown" = the phone cannot tell us; the person looks once).
  final String state;

  /// Which page fixes it: notifications | battery | autostart | access | voice | '' (nothing to open).
  final String fix;

  bool get needsLook => state != 'ok';
}

/// The checks for this phone from the native status (payment alerts channel). An empty list = not an Android phone.
List<AskodoxPhoneCheck> askodoxPhoneChecks(Map<String, Object?> status) {
  if (status['unavailable'] == true || status['error'] != null) return const [];
  String tri(Object? value) => value == true ? 'ok' : (value == false ? 'bad' : 'unknown');
  final wanted = status['enabled'] == true || status['personalEnabled'] == true;
  final canRead = status['listenerDeclared'] == true;
  final allowed = status['listenerAllowed'] == true;
  final connected = (status['connectedAt'] as num?)?.toInt() ?? 0;
  final dropped = (status['disconnectedAt'] as num?)?.toInt() ?? 0;
  final pending = (status['pending'] as num?)?.toInt() ?? 0;
  return [
    AskodoxPhoneCheck('notifications', tri(status['notificationsEnabled']), fix: 'notifications'),
    AskodoxPhoneCheck('battery', tri(status['batteryUnrestricted']), fix: 'battery'),
    // The maker's own "autostart" switch cannot be read by any app: the person looks once.
    if (status['autostartPage'] == true) const AskodoxPhoneCheck('autostart', 'unknown', fix: 'autostart'),
    if (canRead && wanted) AskodoxPhoneCheck('payment_access', allowed ? 'ok' : 'bad', fix: 'access'),
    // Allowed, but the phone cut ASKODOX off after it last connected: the battery rule is the usual cause.
    if (canRead && wanted && allowed)
      AskodoxPhoneCheck('payment_alive', dropped > connected ? 'bad' : 'ok', fix: 'battery'),
    AskodoxPhoneCheck('voice', tri(status['ttsReady']), fix: 'voice'),
    if (status['ttsLanguageOk'] == false) const AskodoxPhoneCheck('voice_language', 'bad', fix: 'voice'),
    if (pending > 0) const AskodoxPhoneCheck('pending_upload', 'bad'),
  ];
}

/// (name, one line on what it means) of a check.
(String, String) askodoxPhoneCheckText(String id, {required bool te}) => switch (id) {
      'notifications' => te
          ? ('ASKODOX నోటిఫికేషన్లు', 'ఆఫ్ ఉంటే payment వచ్చినా, ఆర్డర్ వచ్చినా ఫోన్ చెప్పదు.')
          : ('ASKODOX notifications', 'When off, the phone stays silent for payments and orders.'),
      'battery' => te
          ? ('బ్యాటరీ పరిమితి', 'ఫోన్ బ్యాటరీ ఆదా కోసం ASKODOX ని ఆపేస్తే payment voice రాదు.')
          : ('Battery limit', 'If the phone puts ASKODOX to sleep to save battery, payment voice stops.'),
      'autostart' => te
          ? ('Autostart', 'ఫోన్ రీస్టార్ట్ అయ్యాక ASKODOX తనంతట మొదలవ్వాలి. ఇది ఫోన్ మాకు చెప్పదు, ఒకసారి చూడండి.')
          : ('Autostart', 'ASKODOX must start by itself after a restart. The phone cannot tell us: look once.'),
      'payment_access' => te
          ? ('Payment voice అనుమతి', 'Payment message వచ్చినప్పుడు చదివి చెప్పడానికి ఈ అనుమతి కావాలి.')
          : ('Payment voice permission', 'Needed to read a payment message aloud when it arrives.'),
      'payment_alive' => te
          ? ('ఫోన్ ASKODOX ని ఆపేసింది', 'అనుమతి ఉంది, కానీ ఫోన్ మధ్యలో ఆపేసింది. బ్యాటరీ పరిమితి తీసేయండి.')
          : ('The phone stopped ASKODOX', 'Allowed, but the phone cut it off. Remove the battery limit.'),
      'voice' => te
          ? ('ఫోన్ voice', 'నెట్ లేనప్పుడు ఫోన్ సొంత voice తో చెప్తుంది. అది సిద్ధంగా లేదు.')
          : ('Phone voice', 'Without internet the phone speaks with its own voice. It is not ready.'),
      'voice_language' => te
          ? ('Voice భాష', 'మీ భాష voice ఫోన్ లో లేదు. Download చేస్తే నెట్ లేకపోయినా వినిపిస్తుంది.')
          : ('Voice language', 'Your language voice is not on the phone. Download it to hear without internet.'),
      'pending_upload' => te
          ? ('పంపనివి మిగిలాయి', 'నెట్ లేక కొన్ని payments shop కి చేరలేదు. నెట్ వచ్చాక వాటంతట అవే వెళ్తాయి.')
          : ('Not sent yet', 'Some payments did not reach the shop (no internet). They go by themselves later.'),
      _ => (id, ''),
    };

/// The phone maker's family: makers that share one settings layout.
String askodoxPhoneFamily(String maker) {
  final m = maker.toLowerCase();
  bool any(List<String> names) => names.any(m.contains);
  if (any(['samsung'])) return 'samsung';
  if (any(['xiaomi', 'redmi', 'poco'])) return 'xiaomi';
  if (any(['vivo', 'iqoo'])) return 'vivo';
  if (any(['realme'])) return 'realme';
  if (any(['oppo'])) return 'oppo';
  if (any(['oneplus'])) return 'oneplus';
  if (any(['motorola', 'lenovo'])) return 'motorola';
  if (any(['google'])) return 'google';
  if (any(['nothing'])) return 'nothing';
  if (any(['tecno', 'infinix', 'itel'])) return 'transsion';
  if (any(['huawei', 'honor'])) return 'huawei';
  if (any(['asus'])) return 'asus';
  if (any(['nokia', 'hmd'])) return 'nokia';
  if (any(['lava', 'micromax'])) return 'lava';
  return 'other';
}

/// Where the battery rule lives on each family's phone, (English, Telugu). 'other' is plain Android.
const askodoxBatterySteps = <String, (String, String)>{
  'samsung': ('Battery → Unrestricted. Also Settings → Battery → Background usage limits: keep ASKODOX out of "Sleeping apps".',
      'Battery → Unrestricted ఎంచుకోండి. Settings → Battery → Background usage limits లో "Sleeping apps" నుంచి ASKODOX తీసేయండి.'),
  'xiaomi': ('Battery saver → No restrictions.', 'Battery saver → No restrictions ఎంచుకోండి.'),
  'vivo': ('Battery → Background power consumption → allow high background use.',
      'Battery → Background power consumption → High background power consumption ఆన్ చేయండి.'),
  'realme': ('Battery usage → Allow background activity, and turn off "Auto-optimise".',
      'Battery usage → Allow background activity ఆన్, "Auto-optimise" ఆఫ్ చేయండి.'),
  'oppo': ('Battery usage → Allow background activity.', 'Battery usage → Allow background activity ఆన్ చేయండి.'),
  'oneplus': ('Battery → Unrestricted (Don\'t optimise).', 'Battery → Unrestricted (Don\'t optimise) ఎంచుకోండి.'),
  'motorola': ('Battery → Unrestricted.', 'Battery → Unrestricted ఎంచుకోండి.'),
  'google': ('App battery usage → Unrestricted.', 'App battery usage → Unrestricted ఎంచుకోండి.'),
  'nothing': ('App battery usage → Unrestricted.', 'App battery usage → Unrestricted ఎంచుకోండి.'),
  'transsion': ('Battery → Unrestricted, and in Phone Master keep ASKODOX out of "Auto clean".',
      'Battery → Unrestricted ఎంచుకోండి. Phone Master లో "Auto clean" నుంచి ASKODOX తీసేయండి.'),
  'huawei': ('Battery → App launch → ASKODOX: manage manually, all three switches on.',
      'Battery → App launch → ASKODOX: Manage manually, మూడు switches ఆన్ చేయండి.'),
  'asus': ('Battery → Unrestricted, and allow ASKODOX in Mobile Manager → Auto-start.',
      'Battery → Unrestricted ఎంచుకోండి. Mobile Manager → Auto-start లో ASKODOX ఆన్ చేయండి.'),
  'nokia': ('Battery → Unrestricted.', 'Battery → Unrestricted ఎంచుకోండి.'),
  'lava': ('Battery → Unrestricted.', 'Battery → Unrestricted ఎంచుకోండి.'),
  'other': ('Battery → Unrestricted (or "Don\'t optimise").', 'Battery → Unrestricted (లేదా "Don\'t optimise") ఎంచుకోండి.'),
};

/// Where "autostart" lives, (English, Telugu), for the families that have such a page.
const askodoxAutostartSteps = <String, (String, String)>{
  'xiaomi': ('Autostart → turn ASKODOX on.', 'Autostart → ASKODOX ఆన్ చేయండి.'),
  'vivo': ('Autostart → turn ASKODOX on.', 'Autostart → ASKODOX ఆన్ చేయండి.'),
  'realme': ('Auto launch → turn ASKODOX on.', 'Auto launch → ASKODOX ఆన్ చేయండి.'),
  'oppo': ('Auto launch (Startup manager) → turn ASKODOX on.', 'Auto launch (Startup manager) → ASKODOX ఆన్ చేయండి.'),
  'oneplus': ('Auto launch → turn ASKODOX on.', 'Auto launch → ASKODOX ఆన్ చేయండి.'),
  'transsion': ('Auto-start management → turn ASKODOX on.', 'Auto-start management → ASKODOX ఆన్ చేయండి.'),
  'huawei': ('App launch → ASKODOX: manage manually, Auto-launch on.', 'App launch → ASKODOX: Manage manually, Auto-launch ఆన్.'),
  'asus': ('Auto-start manager → turn ASKODOX on.', 'Auto-start manager → ASKODOX ఆన్ చేయండి.'),
  'other': ('Find "Autostart" / "Auto launch" and turn ASKODOX on.', '"Autostart" / "Auto launch" వెతికి ASKODOX ఆన్ చేయండి.'),
};

/// What to do on the page that opens, for this maker's phone. '' when there is nothing to open.
String askodoxPhoneFixSteps(String fix, String maker, {required bool te}) {
  final family = askodoxPhoneFamily(maker);
  (String, String) pick(Map<String, (String, String)> table) => table[family] ?? table['other']!;
  final (String en, String tel) = switch (fix) {
    'notifications' => ('Turn "Allow notifications" on.', '"Allow notifications" ఆన్ చేయండి.'),
    'battery' => pick(askodoxBatterySteps),
    'autostart' => pick(askodoxAutostartSteps),
    'access' => ('Find ASKODOX in the list and turn it on. Press "Allow" when the phone asks.',
        'List లో ASKODOX వెతికి ఆన్ చేయండి. ఫోన్ అడిగితే "Allow" నొక్కండి.'),
    'voice' => ('Download the voice of your language, then come back.', 'మీ భాష voice download చేసి, వెనక్కి రండి.'),
    _ => ('', ''),
  };
  return te ? tel : en;
}

/// The report the person may send: only the check ids and states, the maker and the app build. Nothing else.
Map<String, Object?> askodoxPhoneReport(List<AskodoxPhoneCheck> checks,
        {required String maker, required int appBuild, String why = 'user_asked'}) =>
    {
      'consent': true,
      'maker': maker,
      'android': '',
      'app_build': '$appBuild',
      'why': why,
      'checks': {for (final c in checks) c.id: c.state},
    };
