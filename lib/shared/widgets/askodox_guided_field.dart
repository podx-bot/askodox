import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/guide/in_app_guide.dart' show askodoxGuideSpeakerProvider;
import 'askodox_mascot.dart';

/// What a field is for, an example, and a check that says how to write it
/// right. One catalogue ([AskodoxFieldGuides]) serves every form.
class AskodoxFieldGuide {
  const AskodoxFieldGuide({
    required this.exampleEn,
    required this.exampleTe,
    required this.helpEn,
    required this.helpTe,
    this.optional = false,
    this.check,
  });

  final String exampleEn;
  final String exampleTe;
  final String helpEn;
  final String helpTe;
  final bool optional;

  /// Returns (en, te) "write it like this" when the value is not right.
  final (String, String)? Function(String value)? check;

  String example(bool te) => te ? exampleTe : exampleEn;
  String help(bool te) => te ? helpTe : helpEn;

  /// null = fine (or empty and optional); otherwise the message to show.
  String? problem(String raw, bool te) {
    final value = raw.trim();
    if (value.isEmpty) return null; // empty: no complaint while typing
    final p = check?.call(value);
    return p == null ? null : (te ? p.$2 : p.$1);
  }
}

final _letters = RegExp(r'\p{L}', unicode: true);
final _digits = RegExp(r'\d');

(String, String)? _minText(String v, int n, String en, String te) => v.length < n ? (en, te) : null;

class AskodoxFieldGuides {
  static const name = AskodoxFieldGuide(
    exampleEn: 'e.g. Lakshmi Devi',
    exampleTe: 'ఉదా: లక్ష్మీ దేవి',
    helpEn: 'Your full name as customers should see it. Letters only, no phone number.',
    helpTe: 'కస్టమర్లకు కనిపించాల్సిన మీ పూర్తి పేరు. అక్షరాలు మాత్రమే, ఫోన్ నంబర్ వద్దు.',
    check: _name,
  );
  static (String, String)? _name(String v) {
    if (_digits.hasMatch(v)) return ('A name has no numbers. Write it like: Lakshmi Devi', 'పేరులో అంకెలు ఉండవు. ఇలా రాయండి: లక్ష్మీ దేవి');
    if (!_letters.hasMatch(v) || v.length < 2) return ('Write your full name, like: Lakshmi Devi', 'పూర్తి పేరు రాయండి, ఇలా: లక్ష్మీ దేవి');
    return null;
  }

  static const town = AskodoxFieldGuide(
    exampleEn: 'e.g. Vuyyuru, Krishna district',
    exampleTe: 'ఉదా: ఉయ్యూరు, కృష్ణా జిల్లా',
    helpEn: 'Your town or village and the area, so nearby customers find you.',
    helpTe: 'మీ ఊరు / గ్రామం, ప్రాంతం -- దగ్గరి కస్టమర్లు మిమ్మల్ని కనుగొనడానికి.',
    check: _town,
  );
  static (String, String)? _town(String v) => !_letters.hasMatch(v) || v.length < 3
      ? ('Write your town and area, like: Vuyyuru, Krishna district', 'ఊరు, ప్రాంతం రాయండి, ఇలా: ఉయ్యూరు, కృష్ణా జిల్లా')
      : null;

  static const email = AskodoxFieldGuide(
    exampleEn: 'e.g. name@gmail.com',
    exampleTe: 'ఉదా: name@gmail.com',
    helpEn: 'Optional. Only for receipts and account messages.',
    helpTe: 'ఐచ్ఛికం. రసీదులు, ఖాతా సందేశాల కోసం మాత్రమే.',
    optional: true,
    check: _email,
  );
  static (String, String)? _email(String v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(v)
      ? null
      : ('An e-mail looks like: name@gmail.com', 'ఈ-మెయిల్ ఇలా ఉంటుంది: name@gmail.com');

  static const shopName = AskodoxFieldGuide(
    exampleEn: 'e.g. Sri Lakshmi Kirana',
    exampleTe: 'ఉదా: శ్రీ లక్ష్మీ కిరాణా',
    helpEn: 'The name customers know your shop or service by.',
    helpTe: 'కస్టమర్లకు తెలిసిన మీ షాప్ / సర్వీస్ పేరు.',
    check: _shopName,
  );
  static (String, String)? _shopName(String v) =>
      _minText(v, 2, 'Write the shop name, like: Sri Lakshmi Kirana', 'షాప్ పేరు రాయండి, ఇలా: శ్రీ లక్ష్మీ కిరాణా');

  static const shopAddress = AskodoxFieldGuide(
    exampleEn: 'e.g. Main Road, near Bus Stand, Vuyyuru',
    exampleTe: 'ఉదా: మెయిన్ రోడ్, బస్ స్టాండ్ దగ్గర, ఉయ్యూరు',
    helpEn: 'Street, a landmark near you and the town -- so customers can reach you.',
    helpTe: 'వీధి, దగ్గరి గుర్తు (ల్యాండ్‌మార్క్), ఊరు -- కస్టమర్లు చేరుకోవడానికి.',
    check: _shopAddress,
  );
  static (String, String)? _shopAddress(String v) => !_letters.hasMatch(v) || v.length < 6
      ? ('Add the street, a landmark and the town, like: Main Road, near Bus Stand, Vuyyuru',
          'వీధి, ల్యాండ్‌మార్క్, ఊరు రాయండి, ఇలా: మెయిన్ రోడ్, బస్ స్టాండ్ దగ్గర, ఉయ్యూరు')
      : null;

  static const category = AskodoxFieldGuide(
    exampleEn: 'e.g. Groceries, Mobile repair',
    exampleTe: 'ఉదా: కిరాణా, మొబైల్ రిపేర్',
    helpEn: 'What you sell or the service you give, in a few words.',
    helpTe: 'మీరు అమ్మేది లేదా ఇచ్చే సేవ, కొన్ని మాటల్లో.',
    check: _category,
  );
  static (String, String)? _category(String v) =>
      _minText(v, 3, 'Write what you sell, like: Groceries', 'ఏమి అమ్ముతారో రాయండి, ఇలా: కిరాణా');

  static const gstin = AskodoxFieldGuide(
    exampleEn: 'e.g. 37ABCDE1234F1Z5',
    exampleTe: 'ఉదా: 37ABCDE1234F1Z5',
    helpEn: 'Optional. 15 letters and numbers from your GST certificate.',
    helpTe: 'ఐచ్ఛికం. మీ GST సర్టిఫికేట్‌లోని 15 అక్షరాలు, అంకెలు.',
    optional: true,
    check: _gstin,
  );
  static (String, String)? _gstin(String v) =>
      RegExp(r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(v.toUpperCase())
          ? null
          : ('GSTIN has 15 characters, like: 37ABCDE1234F1Z5', 'GSTIN లో 15 అక్షరాలు ఉంటాయి, ఇలా: 37ABCDE1234F1Z5');

  static const offerTitle = AskodoxFieldGuide(
    exampleEn: 'e.g. 10% off on rice bags',
    exampleTe: 'ఉదా: బియ్యం బస్తాలపై 10% తగ్గింపు',
    helpEn: 'The offer in a few words: what is cheaper and by how much.',
    helpTe: 'ఆఫర్ కొన్ని మాటల్లో: ఏది, ఎంత తక్కువ.',
    check: _offerTitle,
  );
  static (String, String)? _offerTitle(String v) =>
      _minText(v, 4, 'Say what the offer is, like: 10% off on rice bags', 'ఆఫర్ ఏంటో రాయండి, ఇలా: బియ్యం బస్తాలపై 10% తగ్గింపు');

  static const offerValue = AskodoxFieldGuide(
    exampleEn: 'e.g. 50 (₹) or 10%',
    exampleTe: 'ఉదా: 50 (₹) లేదా 10%',
    helpEn: 'The discount: an amount in rupees, or a percent with %.',
    helpTe: 'తగ్గింపు: రూపాయల్లో మొత్తం, లేదా % తో శాతం.',
    check: _offerValue,
  );
  static (String, String)? _offerValue(String v) {
    final m = RegExp(r'^₹?\s*(\d+(\.\d+)?)\s*(%)?$').firstMatch(v.replaceAll(',', ''));
    final n = m == null ? null : double.tryParse(m.group(1)!);
    if (n == null || n <= 0) return ('Only a number: 50 for ₹50, or 10% for a percent', 'అంకె మాత్రమే: ₹50 కి 50, శాతానికి 10%');
    if (m!.group(3) != null && n > 100) return ('A percent cannot be more than 100%', 'శాతం 100% కంటే ఎక్కువ ఉండదు');
    return null;
  }

  static const faqTopic = AskodoxFieldGuide(
    exampleEn: 'e.g. Do you deliver?',
    exampleTe: 'ఉదా: డెలివరీ చేస్తారా?',
    helpEn: 'A question customers often ask you.',
    helpTe: 'కస్టమర్లు తరచూ అడిగే ప్రశ్న.',
    check: _faqTopic,
  );
  static (String, String)? _faqTopic(String v) =>
      _minText(v, 3, 'Write the question, like: Do you deliver?', 'ప్రశ్న రాయండి, ఇలా: డెలివరీ చేస్తారా?');

  static const faqAnswer = AskodoxFieldGuide(
    exampleEn: 'e.g. Yes, free delivery within 3 km.',
    exampleTe: 'ఉదా: అవును, 3 కి.మీ లోపు ఉచిత డెలివరీ.',
    helpEn: 'Your answer, exactly as it should be sent to the customer.',
    helpTe: 'కస్టమర్‌కు పంపాల్సిన జవాబు, ఉన్నది ఉన్నట్టు.',
    check: _faqAnswer,
  );
  static (String, String)? _faqAnswer(String v) =>
      _minText(v, 3, 'Write the full answer, like: Yes, free delivery within 3 km.', 'పూర్తి జవాబు రాయండి.');

  static const videoTitle = AskodoxFieldGuide(
    exampleEn: 'e.g. Fresh mangoes from our farm',
    exampleTe: 'ఉదా: మా తోట నుంచి తాజా మామిడి పండ్లు',
    helpEn: 'A short title: what the video shows.',
    helpTe: 'చిన్న టైటిల్: వీడియోలో ఏముందో.',
    check: _videoTitle,
  );
  static (String, String)? _videoTitle(String v) =>
      _minText(v, 3, 'Say what the video shows, like: Fresh mangoes from our farm', 'వీడియోలో ఏముందో రాయండి.');

  static const price = AskodoxFieldGuide(
    exampleEn: 'e.g. 250',
    exampleTe: 'ఉదా: 250',
    helpEn: 'The selling price in rupees -- numbers only.',
    helpTe: 'అమ్మే ధర రూపాయల్లో -- అంకెలు మాత్రమే.',
    check: _price,
  );
  static (String, String)? _price(String v) {
    final n = double.tryParse(v.replaceAll(RegExp(r'[₹,\s]'), ''));
    return n == null || n <= 0 ? ('Only the amount in numbers, like: 250', 'అంకెల్లో మొత్తం మాత్రమే, ఇలా: 250') : null;
  }

  static const variant = AskodoxFieldGuide(
    exampleEn: 'e.g. Size: 8, 9, 10',
    exampleTe: 'ఉదా: Size: 8, 9, 10',
    helpEn: 'Optional. Sizes, colours or weights you have, separated by commas.',
    helpTe: 'ఐచ్ఛికం. మీ దగ్గర ఉన్న సైజులు, రంగులు, బరువులు -- కామాలతో.',
    optional: true,
  );

  static const facts = AskodoxFieldGuide(
    exampleEn: 'e.g. Basmati rice 25 kg, ₹1,800, free delivery in Vuyyuru',
    exampleTe: 'ఉదా: బాస్మతి బియ్యం 25 కిలోలు, ₹1,800, ఉయ్యూరులో ఉచిత డెలివరీ',
    helpEn: 'Real facts only: product, price, offer, place. ASKODOX writes from these and never invents.',
    helpTe: 'నిజమైన వివరాలు మాత్రమే: వస్తువు, ధర, ఆఫర్, ప్రాంతం. వీటితోనే రాస్తుంది, ఏదీ కల్పించదు.',
    check: _facts,
  );
  static (String, String)? _facts(String v) => v.length < 10
      ? ('Add a little more: product, price and place', 'ఇంకొంచెం రాయండి: వస్తువు, ధర, ప్రాంతం')
      : null;
}

/// A text field that guides: the example inside the blank, a green tick when
/// it is right, "write it like this" when it is not, and a mascot "?" that
/// explains the field (and says it aloud).
class AskodoxGuidedField extends ConsumerStatefulWidget {
  const AskodoxGuidedField({
    super.key,
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.guide,
    this.keyboardType,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.onChanged,
  });

  /// Key of the inner TextField (guides and tests point at it).
  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final AskodoxFieldGuide guide;
  final TextInputType? keyboardType;
  final int? maxLines;
  final int? minLines;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  @override
  ConsumerState<AskodoxGuidedField> createState() => _AskodoxGuidedFieldState();
}

class _AskodoxGuidedFieldState extends ConsumerState<AskodoxGuidedField> {
  final _focus = FocusNode();
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(() {
      if (!_focus.hasFocus && widget.controller.text.isNotEmpty) setState(() => _touched = true);
    });
  }

  @override
  void didUpdateWidget(AskodoxGuidedField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    if (!mounted) return;
    // Judge while typing once a few letters are in (or after leaving the field).
    if (widget.controller.text.trim().length >= 3) _touched = true;
    setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  bool get _te => Localizations.maybeLocaleOf(context)?.languageCode == 'te';

  Future<void> _explain(String? problem) async {
    final te = _te;
    final line = problem ?? widget.guide.help(te);
    unawaited(ref.read(askodoxGuideSpeakerProvider)(
            problem == null ? '${widget.guide.help(te)} ${widget.guide.example(te)}' : problem, te ? 'te' : 'en')
        .catchError((_) {}));
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AskodoxMascot(mood: problem == null ? AskodoxMascotMood.happy : AskodoxMascotMood.confused, size: 64),
            const SizedBox(width: 14),
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                const SizedBox(height: 6),
                Text(line, key: const Key('askodoxFieldHelpText'), style: const TextStyle(fontSize: 14.5, height: 1.35)),
                const SizedBox(height: 8),
                Text(widget.guide.example(te),
                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF6C4DFF), fontWeight: FontWeight.w700)),
                if (widget.guide.optional) ...[
                  const SizedBox(height: 6),
                  Text(te ? 'ఇది ఐచ్ఛికం -- ఖాళీగా వదిలేయొచ్చు.' : 'This one is optional -- you may leave it empty.',
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF667085))),
                ],
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final te = _te;
    final text = widget.controller.text.trim();
    final problem = _touched ? widget.guide.problem(text, te) : null;
    final ok = text.isNotEmpty && widget.guide.problem(text, te) == null;
    final mood = problem != null
        ? AskodoxMascotMood.confused
        : ok
            ? AskodoxMascotMood.success
            : AskodoxMascotMood.happy;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: TextField(
        key: widget.fieldKey,
        controller: widget.controller,
        focusNode: _focus,
        keyboardType: widget.keyboardType,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        maxLength: widget.maxLength,
        onChanged: widget.onChanged,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.guide.example(te),
          hintStyle: const TextStyle(color: Color(0xFFA0A8B8)),
          floatingLabelBehavior: FloatingLabelBehavior.always,
          errorText: problem,
          errorMaxLines: 3,
          errorStyle: const TextStyle(color: Color(0xFFB54708)),
          errorBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF79009))),
          focusedErrorBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFF79009), width: 2)),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (ok)
              Icon(Icons.check_circle_rounded,
                  key: ValueKey('askodoxFieldOk-${_keyName(widget.fieldKey)}'), color: const Color(0xFF12B76A), size: 22),
            IconButton(
              key: ValueKey('askodoxFieldHelp-${_keyName(widget.fieldKey)}'),
              tooltip: te ? 'ఎలా రాయాలి?' : 'How to fill this?',
              visualDensity: VisualDensity.compact,
              onPressed: () => _explain(problem),
              icon: AskodoxMascot(mood: mood, size: 28),
            ),
          ]),
        ),
      ),
    );
  }

  static String _keyName(Key key) => key is ValueKey ? '${key.value}' : key.toString();
}
