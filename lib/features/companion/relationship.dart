import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ASKODOX Friend -- Relationship Companion. ASKO is ONE character (a
/// child-like, gender-neutral AI friend); only how it addresses the person
/// changes, as they choose. Used only in ASKO's own lines (guide, field help,
/// greetings) -- never in chat replies, search or voice-mode settings.
enum AskodoxRelation { friend, anna, akka, thammudu, chelli, mama, bava, attha, babai, pinni }

class AskodoxRelationInfo {
  const AskodoxRelationInfo(this.labelEn, this.labelTe, this.callEn, this.callTe);

  /// Shown in the picker.
  final String labelEn;
  final String labelTe;

  /// How ASKO calls the person ("Anna", "అన్నయ్యా").
  final String callEn;
  final String callTe;
}

const askodoxRelations = <AskodoxRelation, AskodoxRelationInfo>{
  AskodoxRelation.friend: AskodoxRelationInfo('Friend', 'ఫ్రెండ్', 'friend', 'ఫ్రెండ్'),
  AskodoxRelation.anna: AskodoxRelationInfo('Anna (elder brother)', 'అన్నయ్య', 'Anna', 'అన్నయ్యా'),
  AskodoxRelation.akka: AskodoxRelationInfo('Akka (elder sister)', 'అక్క', 'Akka', 'అక్కా'),
  AskodoxRelation.thammudu: AskodoxRelationInfo('Thammudu (younger brother)', 'తమ్ముడు', 'Thammudu', 'తమ్ముడూ'),
  AskodoxRelation.chelli: AskodoxRelationInfo('Chelli (younger sister)', 'చెల్లి', 'Chelli', 'చెల్లీ'),
  AskodoxRelation.mama: AskodoxRelationInfo('Mama', 'మామ', 'Mama', 'మామా'),
  AskodoxRelation.bava: AskodoxRelationInfo('Bava', 'బావ', 'Bava', 'బావా'),
  AskodoxRelation.attha: AskodoxRelationInfo('Attha', 'అత్త', 'Attha', 'అత్తా'),
  AskodoxRelation.babai: AskodoxRelationInfo('Babai', 'బాబాయ్', 'Babai', 'బాబాయ్'),
  AskodoxRelation.pinni: AskodoxRelationInfo('Pinni', 'పిన్ని', 'Pinni', 'పిన్నీ'),
};

class AskodoxRelationController extends StateNotifier<AskodoxRelation> {
  AskodoxRelationController() : super(AskodoxRelation.friend) {
    _load();
  }

  static const key = 'askodox.companion.relation';

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(key);
      final match = AskodoxRelation.values.where((r) => r.name == saved);
      if (match.isNotEmpty && mounted) state = match.first;
    } catch (_) {}
  }

  Future<void> choose(AskodoxRelation relation) async {
    state = relation;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, relation.name);
    } catch (_) {}
  }
}

final askodoxRelationProvider =
    StateNotifierProvider<AskodoxRelationController, AskodoxRelation>((ref) => AskodoxRelationController());

/// "అన్నయ్యా" / "Anna" for the chosen relation.
String askodoxCallName(AskodoxRelation relation, {required bool telugu}) {
  final info = askodoxRelations[relation]!;
  return telugu ? info.callTe : info.callEn;
}

/// ASKO's own short greeting: "హాయ్ అన్నయ్యా!" / "Hi Anna!".
String askodoxGreeting(AskodoxRelation relation, {required bool telugu}) =>
    telugu ? 'హాయ్ ${askodoxCallName(relation, telugu: true)}!' : 'Hi ${askodoxCallName(relation, telugu: false)}!';

/// A guide line addressed to the person: "అన్నయ్యా, `line`".
String askodoxAddressed(String line, AskodoxRelation relation, {required bool telugu}) {
  var rest = line;
  // English: "Anna, the discount ..." (keep "I", "ASKO", "GSTIN" as written).
  if (!telugu && rest.length > 1 && RegExp(r'^[A-Z][a-z]').hasMatch(rest)) {
    rest = rest[0].toLowerCase() + rest.substring(1);
  }
  return '${askodoxCallName(relation, telugu: telugu)}, $rest';
}

/// ASKO's "done" line: "Done, Anna!" / "పూర్తయింది అన్నయ్యా!".
String askodoxDoneLine(AskodoxRelation relation, {required bool telugu}) => telugu
    ? 'పూర్తయింది ${askodoxCallName(relation, telugu: true)}!'
    : 'Done, ${askodoxCallName(relation, telugu: false)}!';
