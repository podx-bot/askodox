/// Payment voice alerts: the one-question-at-a-time setup.
///
/// Pure (no Flutter): the phone's own status + the allowed payment apps on this phone go in, the ordered list of
/// setup steps comes out. The screen shows the FIRST unfinished step as one question with "OK" / "Not now", so a
/// person never has to hunt through Android settings. Steps the phone can check are checked again every time the
/// person comes back to ASKODOX; the two it cannot check (another app's notification switch, "did you hear it?")
/// count as done once the person confirmed them.
library;

typedef AskodoxSetupJson = Map<String, Object?>;

class AskodoxPayAlertSetupStep {
  const AskodoxPayAlertSetupStep(this.id, {required this.done, this.package, this.appLabel = '', this.ownerOnly = false});

  /// shop_on | access | battery | app_notifications:<package> | app_battery:<package> | sound
  final String id;
  final bool done;

  /// The payment app this step is about (app_* steps only).
  final String? package;
  final String appLabel;

  /// Only the shop owner can do it (staff see "ask the owner").
  final bool ownerOnly;

  String get kind => id.contains(':') ? id.substring(0, id.indexOf(':')) : id;
}

/// The person's own confirmations (kept on the phone): `app_notifications:<package>` and `sound`.
const askodoxPayAlertSetupConfirmedKey = 'askodox.pos.payalert.setup.confirmed.v1';

List<AskodoxPayAlertSetupStep> askodoxPayAlertSetupSteps({
  required AskodoxSetupJson status,
  required AskodoxSetupJson settings,
  required List<AskodoxSetupJson> apps,
  required Set<String> confirmed,
  bool phoneOnly = false,
}) {
  if (status['unavailable'] == true) return const []; // not an Android phone: nothing to set up
  final canReadNotifications = status['listenerDeclared'] != false; // Play build
  final labels = settings['apps'] is Map ? (settings['apps'] as Map) : const {};
  final steps = <AskodoxPayAlertSetupStep>[
    AskodoxPayAlertSetupStep('shop_on',
        done: settings['enabled'] == true, ownerOnly: !(phoneOnly || settings['can_edit'] == true)),
    if (canReadNotifications) AskodoxPayAlertSetupStep('access', done: status['listenerAllowed'] == true),
    // An older app without this key answers nothing: never block the person on a step the phone cannot check.
    AskodoxPayAlertSetupStep('battery', done: status['batteryUnrestricted'] != false),
  ];
  if (canReadNotifications) {
    for (final app in apps) {
      if (app['installed'] != true) continue;
      final pkg = '${app['package'] ?? ''}';
      if (pkg.isEmpty) continue;
      final label = '${labels[pkg] ?? pkg}';
      final seen = app['lastSeenAt'] is num && (app['lastSeenAt'] as num) > 0;
      steps
        ..add(AskodoxPayAlertSetupStep('app_notifications:$pkg',
            done: seen || confirmed.contains('app_notifications:$pkg'), package: pkg, appLabel: label))
        ..add(AskodoxPayAlertSetupStep('app_battery:$pkg', done: app['batteryUnrestricted'] == true, package: pkg, appLabel: label));
    }
  }
  steps.add(AskodoxPayAlertSetupStep('sound', done: confirmed.contains('sound')));
  return steps;
}

/// The step to ask now: the first unfinished one the person did not put off in this visit.
AskodoxPayAlertSetupStep? askodoxPayAlertNextStep(List<AskodoxPayAlertSetupStep> steps, Set<String> putOff) {
  for (final s in steps) {
    if (!s.done && !putOff.contains(s.id)) return s;
  }
  return null;
}

/// (question, one line on what to do) for a step, in Telugu or English. Plain words: no "listener", no
/// "notification access".
(String, String) askodoxPayAlertStepText(AskodoxPayAlertSetupStep step, {required bool te, String maker = ''}) {
  final samsung = maker.contains('samsung');
  final app = step.appLabel;
  return switch (step.kind) {
    'shop_on' => step.ownerOnly
        ? (te ? 'ఈ షాపుకు పేమెంట్ సౌండ్ ఆఫ్ లో ఉంది' : 'Payment sound is off for this shop',
            te ? 'షాప్ యజమాని ఆన్ చేయాలి.' : 'The shop owner has to switch it on.')
        : (te ? 'పేమెంట్ వచ్చినప్పుడు ఫోన్ మాట్లాడాలా?' : 'Should the phone speak when a payment comes?',
            te ? 'ఓకే నొక్కితే ఈ షాపుకు పేమెంట్ సౌండ్ ఆన్ అవుతుంది.' : 'OK switches payment sound on for this shop.'),
    'access' => (
        te ? 'పేమెంట్ మెసేజ్ చదవడానికి అనుమతి ఇవ్వండి' : 'Allow ASKODOX to read payment messages',
        te
            ? 'తెరుచుకునే స్క్రీన్ లో ASKODOX ను ఆన్ చేసి వెనక్కి రండి. పేమెంట్ యాప్‌ల మెసేజ్ లో మొత్తం మాత్రమే చదువుతుంది.'
            : 'Switch ASKODOX on in the next screen, then come back. Only the amount in payment app messages is read.'
      ),
    'battery' => (
        te ? 'ఫోన్ ASKODOX ను ఆపకుండా చూడండి' : 'Stop the phone from putting ASKODOX to sleep',
        samsung
            ? (te
                ? 'తెరుచుకునే పేజీ లో Battery → Unrestricted ఎంచుకోండి. "Manage app if unused" ఆఫ్ చేయండి.'
                : 'In the next page choose Battery → Unrestricted and switch off "Manage app if unused".')
            : (te ? 'తెరుచుకునే లిస్ట్ లో ASKODOX → Allow / Unrestricted ఎంచుకోండి.' : 'In the next list choose ASKODOX → Allow / Unrestricted.')
      ),
    'app_notifications' => (
        te ? '$app నోటిఫికేషన్లు ఆన్ లో ఉంచండి' : 'Keep $app notifications on',
        te
            ? 'తెరుచుకునే పేజీ లో $app నోటిఫికేషన్లు అన్నీ ఆన్ చేసి వెనక్కి రండి. అవి రాకపోతే ASKODOX కి పేమెంట్ తెలియదు.'
            : 'Switch all $app notifications on in the next page, then come back. Without them ASKODOX cannot hear the payment.'
      ),
    'app_battery' => (
        te ? 'ఫోన్ $app ను ఆపకుండా చూడండి' : 'Stop the phone from putting $app to sleep',
        samsung
            ? (te
                ? 'తెరుచుకునే $app పేజీ లో Battery → Unrestricted ఎంచుకోండి. "Manage app if unused" ఆఫ్ చేయండి. లేకపోతే మెసేజ్ ఆలస్యం అవుతుంది.'
                : 'In the $app page choose Battery → Unrestricted and switch off "Manage app if unused", or its messages come late.')
            : (te
                ? 'తెరుచుకునే $app పేజీ లో Battery → Unrestricted / Don\'t optimise ఎంచుకోండి. లేకపోతే మెసేజ్ ఆలస్యం అవుతుంది.'
                : 'In the $app page choose Battery → Unrestricted / Don\'t optimise, or its messages come late.')
      ),
    _ => (
        te ? 'సౌండ్ టెస్ట్' : 'Sound test',
        te ? 'ఓకే నొక్కితే ఫోన్ ఒక టెస్ట్ పేమెంట్ చెబుతుంది.' : 'OK plays a test payment announcement.'
      ),
  };
}
