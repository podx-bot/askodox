/// ASKODOX Work Mode (owner decision 2026-11-07).
///
/// Walking is linked to real-world work: the person picks a job (paddy field,
/// paper boy, house building ...) and every step they walk does a little of
/// that job. There are NO points, rewards, coupons or money anywhere -- the
/// game is the work itself, a daily goal and a shareable record.
///
/// Every job runs in HALF of its real-world time (owner rule: 50 %). A job is
/// a list of stages in the real order (nursery before transplanting, walls
/// before the roof); each stage takes a number of game days, and one game day
/// of work = [askodoxWorkStepsPerDay] steps. Everything here is pure maths so
/// it is unit-tested without a phone.
library;

/// One full day of work.
const askodoxWorkStepsPerDay = 7000;

/// Light goal on the weekly rest day (Sunday).
const askodoxWorkRestDaySteps = 3000;

/// Daily goal by week since the job started: grow gently (never more than
/// about 10 % a week after the first steps) and settle at a full day.
const askodoxWorkWeeklyRamp = <int>[4000, 5000, 6000, 7000];

/// How the job is drawn (one painter per scene).
enum AskodoxWorkScene { field, houses, building, workshop }

class AskodoxWorkStage {
  const AskodoxWorkStage(this.id, this.en, this.te, this.days, this.tipEn, this.tipTe);

  final String id;
  final String en;
  final String te;

  /// Game days (already halved from real life).
  final int days;

  /// A short, general tip about doing this stage well or safely.
  final String tipEn;
  final String tipTe;

  String name(bool te) => te ? this.te : en;
  String tip(bool te) => te ? tipTe : tipEn;
}

class AskodoxWorkJob {
  const AskodoxWorkJob({
    required this.id,
    required this.en,
    required this.te,
    required this.scene,
    required this.realDays,
    required this.walkEn,
    required this.walkTe,
    required this.stages,
  });

  final String id;
  final String en;
  final String te;
  final AskodoxWorkScene scene;

  /// How long the job takes in real life (game time is half of this).
  final int realDays;

  /// What kind of walking suits the job.
  final String walkEn;
  final String walkTe;
  final List<AskodoxWorkStage> stages;

  String name(bool te) => te ? this.te : en;
  String walk(bool te) => te ? walkTe : walkEn;

  /// Game days = sum of the stages (half of [realDays]).
  int get gameDays => stages.fold(0, (sum, s) => sum + s.days);

  /// Steps for the whole job.
  int get totalSteps => gameDays * askodoxWorkStepsPerDay;
}

/// The jobs (first set). Order = how they are listed.
const askodoxWorkJobs = <AskodoxWorkJob>[
  AskodoxWorkJob(
    id: 'paddy',
    en: 'Paddy field',
    te: 'వరి పొలం',
    scene: AskodoxWorkScene.field,
    realDays: 90,
    walkEn: 'Steady walking, row after row',
    walkTe: 'స్థిరమైన నడక, వరుస తర్వాత వరుస',
    stages: [
      AskodoxWorkStage('nursery', 'Raise the nursery', 'నారు పెంపకం', 7,
          'Healthy, even seedlings make the rest of the season easier.', 'ఆరోగ్యంగా, సమంగా పెరిగిన నారు ఉంటే మిగతా పని సులువు.'),
      AskodoxWorkStage('plough', 'Plough and level', 'దున్నడం, చదును', 5,
          'A level field holds water evenly across the plot.', 'పొలం చదునుగా ఉంటే నీరు అంతటా సమంగా నిలుస్తుంది.'),
      AskodoxWorkStage('transplant', 'Transplant', 'నాట్లు', 9,
          'Leave regular spacing between hills so air and light reach every plant.',
          'కుదుళ్ల మధ్య సమమైన దూరం ఉంచితే ప్రతి మొక్కకు గాలి, వెలుతురు అందుతాయి.'),
      AskodoxWorkStage('water', 'Water and feed', 'నీరు, ఎరువు', 11,
          'Keep a thin, steady layer of water; follow your local agriculture officer for fertiliser.',
          'పలుచని నీటి పొర స్థిరంగా ఉంచండి; ఎరువుల కోసం మీ స్థానిక వ్యవసాయ అధికారి సలహా పాటించండి.'),
      AskodoxWorkStage('weed', 'Remove weeds', 'కలుపు తీయడం', 5,
          'Weeds removed early take less food from the crop.', 'కలుపు తొందరగా తీస్తే పంటకు పోషణ తగ్గదు.'),
      AskodoxWorkStage('harvest', 'Harvest and thresh', 'కోత, నూర్పిడి', 8,
          'Harvest when most grains turn golden.', 'చాలా గింజలు బంగారు రంగుకు మారినప్పుడు కోయండి.'),
    ],
  ),
  AskodoxWorkJob(
    id: 'chilli',
    en: 'Chilli field',
    te: 'మిరప తోట',
    scene: AskodoxWorkScene.field,
    realDays: 120,
    walkEn: 'Steady walking with short stops',
    walkTe: 'స్థిరమైన నడక, మధ్యలో చిన్న విరామాలు',
    stages: [
      AskodoxWorkStage('nursery', 'Raise seedlings', 'నారు పెంపకం', 10,
          'Raised nursery beds drain better.', 'ఎత్తైన నారుమడులలో నీరు బాగా పారుతుంది.'),
      AskodoxWorkStage('plough', 'Prepare the land', 'నేల సిద్ధం', 6,
          'Loose, well-drained soil suits chilli.', 'వదులుగా, నీరు పారే నేల మిరపకు అనుకూలం.'),
      AskodoxWorkStage('transplant', 'Transplant', 'నాట్లు', 8,
          'Transplant in the cool evening hours.', 'సాయంత్రం చల్లని వేళ నాటండి.'),
      AskodoxWorkStage('water', 'Water and care', 'నీరు, సంరక్షణ', 16,
          'Water often but never let it stand around the roots.', 'తరచుగా నీరు పెట్టండి, కానీ వేర్ల దగ్గర నిలవనీయకండి.'),
      AskodoxWorkStage('flower', 'Flowering care', 'పూత సంరక్షణ', 10,
          'Watch the flowers for pests and ask your agriculture officer before spraying.',
          'పూతపై పురుగులు గమనించండి; మందు చల్లే ముందు వ్యవసాయ అధికారిని అడగండి.'),
      AskodoxWorkStage('pick', 'Pick the chillies', 'కాయ కోత', 10,
          'Pick ripe pods regularly so the plant keeps fruiting.', 'పండిన కాయలు క్రమం తప్పకుండా కోస్తే మొక్క కాస్తూనే ఉంటుంది.'),
    ],
  ),
  AskodoxWorkJob(
    id: 'vegetables',
    en: 'Vegetable garden',
    te: 'కూరగాయల తోట',
    scene: AskodoxWorkScene.field,
    realDays: 60,
    walkEn: 'Easy walking, good for starting',
    walkTe: 'సులువైన నడక, మొదలుపెట్టడానికి మంచిది',
    stages: [
      AskodoxWorkStage('beds', 'Make the beds', 'మడులు చేయడం', 4,
          'Mix compost into the beds before sowing.', 'విత్తే ముందు మడులలో ఎరువు కలపండి.'),
      AskodoxWorkStage('sow', 'Sow', 'విత్తడం', 4,
          'Sow in rows so weeding is easier.', 'వరుసలుగా విత్తితే కలుపు తీయడం సులువు.'),
      AskodoxWorkStage('water', 'Water', 'నీరు పెట్టడం', 10,
          'Morning watering keeps leaves dry by night.', 'ఉదయం నీరు పెడితే రాత్రికి ఆకులు ఆరిపోతాయి.'),
      AskodoxWorkStage('weed', 'Remove weeds', 'కలుపు తీయడం', 4,
          'Pull weeds when the soil is a little moist.', 'నేల కొంచెం తడిగా ఉన్నప్పుడు కలుపు సులువుగా వస్తుంది.'),
      AskodoxWorkStage('harvest', 'Harvest', 'కోత', 8,
          'Pick vegetables young and tender.', 'కూరగాయలు లేతగా ఉన్నప్పుడే కోయండి.'),
    ],
  ),
  AskodoxWorkJob(
    id: 'paper',
    en: 'Paper boy',
    te: 'పేపర్ బాయ్',
    scene: AskodoxWorkScene.houses,
    realDays: 10,
    walkEn: 'Brisk walking between houses',
    walkTe: 'ఇళ్ల మధ్య చురుకైన నడక',
    stages: [
      AskodoxWorkStage('bundle', 'Pick up the bundle', 'పేపర్ కట్ట తీసుకోవడం', 1,
          'Start early; papers are expected before breakfast.', 'తొందరగా మొదలుపెట్టండి; టిఫిన్‌కి ముందే పేపర్ అందాలి.'),
      AskodoxWorkStage('route', 'Learn the route', 'రూట్ నేర్చుకోవడం', 1,
          'Plan the route so you never walk the same lane twice.', 'ఒకే వీధి రెండుసార్లు నడవకుండా రూట్ ప్లాన్ చేయండి.'),
      AskodoxWorkStage('rounds', 'Daily rounds', 'రోజువారీ రౌండ్లు', 2,
          'Look both ways at every crossing.', 'ప్రతి క్రాసింగ్ దగ్గర రెండు వైపులా చూడండి.'),
      AskodoxWorkStage('collect', 'Monthly collection', 'నెలవారీ వసూలు', 1,
          'Keep a small note of who has paid.', 'ఎవరు కట్టారో చిన్న నోట్ రాసుకోండి.'),
    ],
  ),
  AskodoxWorkJob(
    id: 'delivery',
    en: 'Delivery',
    te: 'డెలివరీ',
    scene: AskodoxWorkScene.houses,
    realDays: 14,
    walkEn: 'Walking with stops and turns',
    walkTe: 'ఆగుతూ, మలుపులతో నడక',
    stages: [
      AskodoxWorkStage('pickup', 'Pick up parcels', 'పార్సిళ్లు తీసుకోవడం', 1,
          'Check every parcel label before leaving.', 'బయలుదేరే ముందు ప్రతి పార్సిల్ లేబుల్ చూడండి.'),
      AskodoxWorkStage('sort', 'Sort by lane', 'వీధుల వారీగా సర్దడం', 1,
          'Sort parcels in route order.', 'పార్సిళ్లను రూట్ వరుసలో సర్దండి.'),
      AskodoxWorkStage('deliver', 'Deliver door to door', 'ఇంటింటికీ డెలివరీ', 4,
          'Hand over to the right person and stay polite.', 'సరైన వ్యక్తికే ఇవ్వండి, మర్యాదగా మాట్లాడండి.'),
      AskodoxWorkStage('returns', 'Returns', 'రిటర్న్‌లు', 1,
          'Bring back undelivered parcels the same day.', 'అందని పార్సిళ్లను అదే రోజు తిరిగి తీసుకురండి.'),
    ],
  ),
  AskodoxWorkJob(
    id: 'digging',
    en: 'Digging',
    te: 'తవ్వకం',
    scene: AskodoxWorkScene.building,
    realDays: 20,
    walkEn: 'Intervals: fast, then rest',
    walkTe: 'ఇంటర్వెల్: వేగంగా, తర్వాత విరామం',
    stages: [
      AskodoxWorkStage('mark', 'Mark the ground', 'గుర్తులు వేయడం', 1,
          'Mark the line with string before digging.', 'తవ్వే ముందు దారంతో గీత గుర్తించండి.'),
      AskodoxWorkStage('dig', 'Dig', 'తవ్వడం', 6,
          'Bend the knees, not the back, when lifting soil.', 'మట్టి ఎత్తేటప్పుడు నడుము కాదు, మోకాళ్లు వంచండి.'),
      AskodoxWorkStage('clear', 'Clear the soil', 'మట్టి తరలింపు', 2,
          'Keep the dug soil away from the edge.', 'తవ్విన మట్టిని గుంత అంచుకు దూరంగా పోయండి.'),
      AskodoxWorkStage('level', 'Level the bed', 'అడుగు చదును', 1,
          'A level bed makes the next work strong.', 'అడుగు సమంగా ఉంటే తర్వాతి పని గట్టిగా ఉంటుంది.'),
    ],
  ),
  AskodoxWorkJob(
    id: 'house',
    en: 'House building',
    te: 'ఇల్లు కట్టడం',
    scene: AskodoxWorkScene.building,
    realDays: 60,
    walkEn: 'Intervals with carrying (bricks)',
    walkTe: 'ఇంటర్వెల్, మధ్యలో బరువు మోయడం (ఇటుకలు)',
    stages: [
      AskodoxWorkStage('foundation', 'Foundation', 'పునాది', 6,
          'A strong foundation is cured with water for days.', 'పునాదికి కొన్ని రోజులు నీళ్లు పడితే గట్టిపడుతుంది.'),
      AskodoxWorkStage('walls', 'Walls', 'గోడలు', 10,
          'Wet the bricks before laying them.', 'ఇటుకలు పేర్చే ముందు తడపండి.'),
      AskodoxWorkStage('roof', 'Roof slab', 'స్లాబ్', 7,
          'Wear a helmet when anyone works overhead.', 'పైన పని జరుగుతుంటే హెల్మెట్ పెట్టుకోండి.'),
      AskodoxWorkStage('plaster', 'Plastering', 'ప్లాస్టరింగ్', 4,
          'Keep fresh plaster damp for a few days.', 'కొత్త ప్లాస్టర్‌ను కొన్ని రోజులు తడిగా ఉంచండి.'),
      AskodoxWorkStage('finish', 'Finishing', 'ఫినిషింగ్', 3,
          'Check doors and windows open freely.', 'తలుపులు, కిటికీలు సులువుగా తెరుచుకుంటున్నాయో చూడండి.'),
    ],
  ),
  AskodoxWorkJob(
    id: 'welding',
    en: 'Welding work',
    te: 'వెల్డింగ్ పని',
    scene: AskodoxWorkScene.workshop,
    realDays: 30,
    walkEn: 'Short walks with many breaks',
    walkTe: 'చిన్న నడకలు, ఎక్కువ విరామాలు',
    stages: [
      AskodoxWorkStage('measure', 'Measure and cut', 'కొలత, కటింగ్', 3,
          'Measure twice, cut once.', 'రెండుసార్లు కొలిచి ఒక్కసారే కోయండి.'),
      AskodoxWorkStage('tack', 'Tack weld', 'టాక్ వెల్డ్', 3,
          'Always wear the mask and gloves.', 'ముసుగు, గ్లౌజులు ఎప్పుడూ ధరించండి.'),
      AskodoxWorkStage('weld', 'Full weld', 'పూర్తి వెల్డింగ్', 5,
          'Work with good air flow.', 'గాలి బాగా ఆడే చోట పని చేయండి.'),
      AskodoxWorkStage('grind', 'Grinding', 'గ్రైండింగ్', 2,
          'Eye protection is a must while grinding.', 'గ్రైండింగ్‌లో కళ్లకు రక్షణ తప్పనిసరి.'),
      AskodoxWorkStage('paint', 'Paint', 'పెయింట్', 2,
          'A primer coat stops rust.', 'ప్రైమర్ కోటు తుప్పు రాకుండా చేస్తుంది.'),
    ],
  ),
  AskodoxWorkJob(
    id: 'chicken_shop',
    en: 'Chicken shop',
    te: 'చికెన్ షాప్ పని',
    scene: AskodoxWorkScene.workshop,
    realDays: 30,
    walkEn: 'Short walks with many breaks',
    walkTe: 'చిన్న నడకలు, ఎక్కువ విరామాలు',
    stages: [
      AskodoxWorkStage('market', 'Morning market', 'ఉదయం మార్కెట్', 3,
          'Buy only what you can sell fresh the same day.', 'అదే రోజు తాజాగా అమ్మగలిగినంతే కొనండి.'),
      AskodoxWorkStage('clean', 'Clean the shop', 'షాప్ శుభ్రం', 2,
          'Clean boards and knives keep customers safe.', 'బోర్డులు, కత్తులు శుభ్రంగా ఉంటే కస్టమర్లకు సురక్షితం.'),
      AskodoxWorkStage('serve', 'Serve customers', 'కస్టమర్లకు అమ్మకం', 8,
          'Weigh in front of the customer.', 'కస్టమర్ ముందే తూకం వేయండి.'),
      AskodoxWorkStage('close', 'Close and accounts', 'మూసివేత, లెక్కలు', 2,
          'Write down the sales of the day before you leave.', 'వెళ్లే ముందు ఆ రోజు అమ్మకాలు రాసుకోండి.'),
    ],
  ),
];

AskodoxWorkJob? askodoxWorkJob(String? id) {
  for (final job in askodoxWorkJobs) {
    if (job.id == id) return job;
  }
  return null;
}

/// "What do you already play?" -> the jobs whose walking fits it best.
class AskodoxSportMatch {
  const AskodoxSportMatch(this.id, this.en, this.te, this.jobs, this.howEn, this.howTe);

  final String id;
  final String en;
  final String te;
  final List<String> jobs;
  final String howEn;
  final String howTe;

  String name(bool te) => te ? this.te : en;
  String how(bool te) => te ? howTe : howEn;
}

const askodoxSportMatches = <AskodoxSportMatch>[
  AskodoxSportMatch('walking', 'Morning walk', 'ఉదయం నడక', ['paddy', 'vegetables'],
      'Steady pace; finish the rows of the day.', 'స్థిరమైన వేగం; ఆ రోజు వరుసలు పూర్తి చేయండి.'),
  AskodoxSportMatch('jogging', 'Jogging', 'జాగింగ్', ['paddy', 'chilli'],
      'Steady pace over a longer distance.', 'ఎక్కువ దూరం, స్థిరమైన వేగం.'),
  AskodoxSportMatch('shuttle', 'Shuttle (badminton)', 'షటిల్', ['paper', 'welding'],
      'Short fast bursts, then rest: about 30 seconds fast, 60 seconds easy.',
      'చిన్న వేగవంతమైన పరుగులు, తర్వాత విరామం: సుమారు 30 సెకన్లు వేగం, 60 సెకన్లు నెమ్మది.'),
  AskodoxSportMatch('tennis', 'Tennis', 'టెన్నిస్', ['delivery'],
      'Stop-and-go with turns.', 'ఆగుతూ మొదలుపెడుతూ, మలుపులతో.'),
  AskodoxSportMatch('football', 'Football', 'ఫుట్‌బాల్', ['digging', 'house'],
      'Intervals; carry something light in between if you like.', 'ఇంటర్వెల్; కావాలంటే మధ్యలో తేలికపాటి బరువు.'),
  AskodoxSportMatch('treadmill', 'Treadmill', 'ట్రెడ్‌మిల్', ['paddy', 'chilli'],
      'Steady pace. If the phone does not count treadmill steps, add them by hand.',
      'స్థిరమైన వేగం. ఫోన్ ట్రెడ్‌మిల్ అడుగులు లెక్కించకపోతే చేతితో నమోదు చేయండి.'),
];

/// Where the job stands after [steps] of work.
class AskodoxWorkProgress {
  const AskodoxWorkProgress({
    required this.job,
    required this.steps,
    required this.stageIndex,
    required this.stageFraction,
    required this.overall,
    required this.gameDay,
    required this.done,
  });

  final AskodoxWorkJob job;
  final int steps;
  final int stageIndex;

  /// 0..1 inside the current stage.
  final double stageFraction;

  /// 0..1 of the whole job.
  final double overall;

  /// 1-based game day the work is on (never past the last day).
  final int gameDay;
  final bool done;

  AskodoxWorkStage get stage => job.stages[stageIndex];

  /// Steps still needed to finish the current stage.
  int get stepsLeftInStage {
    var end = 0;
    for (var i = 0; i <= stageIndex; i++) {
      end += job.stages[i].days * askodoxWorkStepsPerDay;
    }
    final left = end - steps;
    return left < 0 ? 0 : left;
  }
}

AskodoxWorkProgress askodoxWorkProgress(AskodoxWorkJob job, int steps) {
  final s = steps < 0 ? 0 : steps;
  final total = job.totalSteps;
  if (s >= total) {
    return AskodoxWorkProgress(
      job: job,
      steps: s,
      stageIndex: job.stages.length - 1,
      stageFraction: 1,
      overall: 1,
      gameDay: job.gameDays,
      done: true,
    );
  }
  var start = 0;
  for (var i = 0; i < job.stages.length; i++) {
    final len = job.stages[i].days * askodoxWorkStepsPerDay;
    if (s < start + len) {
      return AskodoxWorkProgress(
        job: job,
        steps: s,
        stageIndex: i,
        stageFraction: (s - start) / len,
        overall: s / total,
        gameDay: s ~/ askodoxWorkStepsPerDay + 1,
        done: false,
      );
    }
    start += len;
  }
  // Unreachable (s < total), kept for safety.
  return AskodoxWorkProgress(
      job: job, steps: s, stageIndex: 0, stageFraction: 0, overall: 0, gameDay: 1, done: false);
}

/// The day's goal: a gentle weekly ramp from the day the job started, and a
/// light goal on Sunday (rest day).
int askodoxWorkDailyGoal(DateTime startedOn, DateTime today) {
  if (today.weekday == DateTime.sunday) return askodoxWorkRestDaySteps;
  final a = DateTime(startedOn.year, startedOn.month, startedOn.day);
  final b = DateTime(today.year, today.month, today.day);
  final days = b.difference(a).inDays;
  final week = days < 0 ? 0 : days ~/ 7;
  return week < askodoxWorkWeeklyRamp.length ? askodoxWorkWeeklyRamp[week] : askodoxWorkStepsPerDay;
}

/// Title after finishing a job this many times (no points, only a name).
String askodoxWorkLevel(int finished, bool te) {
  if (finished >= 4) return te ? 'మాస్టర్' : 'Master';
  if (finished >= 2) return te ? 'నిపుణుడు' : 'Expert';
  if (finished >= 1) return te ? 'పనివాడు' : 'Worker';
  return te ? 'అప్రెంటిస్' : 'Apprentice';
}

/// yyyy-mm-dd of a local date.
String askodoxWorkDayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Steps between two readings of the phone's step counter (counts since the
/// phone last started). A smaller reading means the phone restarted: the new
/// reading itself is the steps since then. The first reading ever gives 0 --
/// nobody can tell which of those older steps were walked for the game.
int askodoxStepCounterDelta(int? previous, int reading) {
  if (reading < 0) return 0;
  if (previous == null) return 0;
  if (reading < previous) return reading;
  return reading - previous;
}

/// Counts steps from accelerometer magnitudes (m/s²) while the screen is open
/// on phones without a step counter. A step = the magnitude rising above
/// [high] after having dropped below [low], at least [minGap] apart.
class AskodoxStepDetector {
  AskodoxStepDetector({this.high = 11.2, this.low = 9.4, this.minGap = const Duration(milliseconds: 280)});

  final double high;
  final double low;
  final Duration minGap;
  bool _armed = true;
  DateTime? _last;
  int steps = 0;

  /// Feeds one reading; returns true when it completed a step.
  bool add(double magnitude, DateTime at) {
    if (magnitude <= low) {
      _armed = true;
      return false;
    }
    if (_armed && magnitude >= high) {
      final last = _last;
      if (last != null && at.difference(last) < minGap) return false;
      _armed = false;
      _last = at;
      steps++;
      return true;
    }
    return false;
  }
}
