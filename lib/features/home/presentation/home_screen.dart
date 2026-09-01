import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../deal_brain/application/universal_deal_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  static final _telugu = RegExp(r'[\u0C00-\u0C7F]');
  static final _hindi = RegExp(r'[\u0900-\u097F]');
  static final _odia = RegExp(r'[\u0B00-\u0B7F]');

  String _effectiveLanguage() {
    final manual = ref.read(appSettingsProvider).locale?.languageCode;
    if (manual != null) return manual;
    final device = Localizations.localeOf(context).languageCode;
    return const {'en', 'te', 'hi', 'or'}.contains(device) ? device : 'en';
  }

  String _tr(String en, String te, String hi, String or) {
    return switch (_effectiveLanguage()) {
      'te' => te,
      'hi' => hi,
      'or' => or,
      _ => en,
    };
  }

  void _startFlow(String text) {
    if (_telugu.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('te'));
    } else if (_hindi.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('hi'));
    } else if (_odia.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('or'));
    }
    ref.read(universalDealControllerProvider.notifier).start(text);
    context.go('/search');
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _focusNode.requestFocus();
      return;
    }
    _startFlow(text);
  }

  Future<void> _pickLanguage() async {
    final settings = ref.read(appSettingsProvider);
    final selected = settings.locale == null ? 'system' : settings.locale!.languageCode;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(
          brightness: Brightness.light,
          textTheme: Theme.of(context).textTheme.apply(bodyColor: const Color(0xFF14213D), displayColor: const Color(0xFF14213D)),
          radioTheme: const RadioThemeData(fillColor: WidgetStatePropertyAll(Color(0xFF1769FF))),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE8F8ED),
                    child: Icon(Icons.language_rounded, color: Color(0xFF10A53A)),
                  ),
                  title: Text(
                    _tr('Language', 'భాష', 'भाषा', 'ଭାଷା'),
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF14213D)),
                  ),
                  subtitle: Text(
                    _tr(
                      'Auto follows your device language. You can change it anytime.',
                      'ఆటో మీ డివైస్ భాషను అనుసరిస్తుంది. ఎప్పుడైనా మార్చుకోవచ్చు.',
                      'ऑटो आपके डिवाइस की भाषा का उपयोग करता है। आप इसे कभी भी बदल सकते हैं।',
                      'ଅଟୋ ଆପଣଙ୍କ ଡିଭାଇସ୍ ଭାଷାକୁ ବ୍ୟବହାର କରେ। ଯେକୋଣସି ସମୟରେ ବଦଳାଇ ପାରିବେ।',
                    ),
                    style: const TextStyle(color: Color(0xFF667085)),
                  ),
                ),
                _languageChoice(selected, 'system', _tr('Auto / Device language', 'ఆటో / డివైస్ భాష', 'ऑटो / डिवाइस भाषा', 'ଅଟୋ / ଡିଭାଇସ୍ ଭାଷା')),
                _languageChoice(selected, 'en', 'English'),
                _languageChoice(selected, 'hi', 'हिन्दी'),
                _languageChoice(selected, 'te', 'తెలుగు'),
                _languageChoice(selected, 'or', 'ଓଡ଼ିଆ'),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'system') {
      ref.read(appSettingsProvider.notifier).useSystemLocale();
    } else {
      ref.read(appSettingsProvider.notifier).setLocale(Locale(choice));
    }
  }

  Widget _languageChoice(String selected, String value, String label) => RadioListTile<String>(
        value: value,
        groupValue: selected,
        activeColor: const Color(0xFF1769FF),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        onChanged: (choice) => Navigator.pop(context, choice),
        title: Text(label, style: const TextStyle(color: Color(0xFF14213D), fontWeight: FontWeight.w700)),
      );

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(appSettingsProvider);
    final effective = settings.locale?.languageCode ?? Localizations.localeOf(context).languageCode;
    final languageLabel = settings.locale == null
        ? 'Auto'
        : switch (effective) {
            'te' => 'తెలుగు',
            'hi' => 'हिन्दी',
            'or' => 'ଓଡ଼ିଆ',
            _ => 'EN',
          };
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final askFieldBackground = isDark ? const Color(0xFF18213F) : Colors.white;
    final askFieldBorder = isDark ? const Color(0xFF5B63A8) : const Color(0xFFB8CCFF);
    final askFieldText = isDark ? Colors.white : const Color(0xFF14213D);
    final askFieldHint = isDark ? const Color(0xFFCBD5E1) : const Color(0xFF98A2B3);

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: _tr('Menu', 'మెను', 'मेनू', 'ମେନୁ'),
          onPressed: () => context.go('/profile'),
          icon: const Icon(Icons.menu_rounded, color: Color(0xFF14213D)),
        ),
        title: const Text('ASKODOX AI', style: TextStyle(color: Color(0xFF14213D), fontWeight: FontWeight.w900)),
        actions: [
          TextButton.icon(
            key: const Key('askodoxLanguageButton'),
            onPressed: _pickLanguage,
            icon: const Icon(Icons.language_rounded, color: Color(0xFF1769FF)),
            label: Text(languageLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 28),
          children: [
            Center(
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: const Color(0xFFDDE8FF), width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 24, offset: Offset(0, 10))],
                ),
                child: const Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.smart_toy_rounded, size: 62, color: Color(0xFF1769FF)),
                    Positioned(bottom: 13, child: Icon(Icons.graphic_eq_rounded, color: Color(0xFF10A53A), size: 24)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _tr('Hi! I’m ASKODOX AI', 'హాయ్! నేను ASKODOX AI', 'नमस्ते! मैं ASKODOX AI हूँ', 'ନମସ୍କାର! ମୁଁ ASKODOX AI'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: Color(0xFF14213D)),
            ),
            const SizedBox(height: 7),
            Text(
              _tr(
                'Tell me what you need. I’ll understand it, clarify only what’s missing, and find the best match.',
                'మీకు కావాల్సింది చెప్పండి. నేను అర్థం చేసుకుని, అవసరమైనది మాత్రమే అడిగి, సరైన మ్యాచ్ కనుగొంటాను.',
                'आपको क्या चाहिए बताइए। मैं समझकर केवल जरूरी जानकारी पूछूँगा और सही मैच ढूँढूँगा।',
                'ଆପଣଙ୍କୁ କଣ ଦରକାର କୁହନ୍ତୁ। ମୁଁ ବୁଝି କେବଳ ଆବଶ୍ୟକ ତଥ୍ୟ ପଚାରି ସଠିକ୍ ମ୍ୟାଚ୍ ଖୋଜିବି।',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xFF667085)),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: askFieldBackground,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: askFieldBorder, width: 1.5),
                boxShadow: const [BoxShadow(color: Color(0x120B4EFF), blurRadius: 24, offset: Offset(0, 8))],
              ),
              child: TextField(
                key: const Key('askodoxAskField'),
                controller: _controller,
                focusNode: _focusNode,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                minLines: 1,
                maxLines: 4,
                cursorColor: askFieldText,
                style: TextStyle(color: askFieldText, fontSize: 16),
                decoration: InputDecoration(
                  filled: false,
                  hintText: _tr('Talk or type what you need…', 'మీకు ఏమి కావాలో చెప్పండి…', 'अपनी जरूरत बोलें या लिखें…', 'ଆପଣଙ୍କ ଆବଶ୍ୟକତା କୁହନ୍ତୁ କିମ୍ବା ଲେଖନ୍ତୁ…'),
                  hintStyle: TextStyle(color: askFieldHint),
                  prefixIcon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF10A53A)),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('askodoxMicButton'),
                        tooltip: _tr('Voice', 'వాయిస్', 'वॉइस', 'ଭଏସ୍'),
                        onPressed: () => context.go('/discover/voice'),
                        icon: const Icon(Icons.mic_rounded, color: Color(0xFF10A53A)),
                      ),
                      IconButton(
                        key: const Key('askodoxSendButton'),
                        tooltip: _tr('Ask ASKODOX', 'ASKODOXని అడగండి', 'ASKODOX से पूछें', 'ASKODOX କୁ ପଚାରନ୍ତୁ'),
                        onPressed: _submit,
                        icon: const CircleAvatar(backgroundColor: Color(0xFF1769FF), child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20)),
                      ),
                    ],
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_tr('Recent history', 'ఇటీవలి హిస్టరీ', 'हाल की हिस्ट्री', 'ସମ୍ପ୍ରତି ଇତିହାସ'), style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF14213D))),
                TextButton(onPressed: () => context.go('/watchlist'), child: Text(_tr('See all', 'అన్నీ చూడండి', 'सभी देखें', 'ସବୁ ଦେଖନ୍ତୁ'))),
              ],
            ),
            const SizedBox(height: 6),
            _HistoryPreview(
              icon: Icons.health_and_safety_outlined,
              title: _tr('Family health insurance', 'కుటుంబ హెల్త్ ఇన్సూరెన్స్', 'फैमिली हेल्थ इंश्योरेंस', 'ପରିବାର ସ୍ୱାସ୍ଥ୍ୟ ବୀମା'),
              subtitle: _tr('Compare coverage', 'కవరేజ్ పోల్చండి', 'कवरेज की तुलना करें', 'କଭରେଜ୍ ତୁଳନା କରନ୍ତୁ'),
              onTap: () => _startFlow(_tr('I need health insurance for my family', 'నా కుటుంబానికి హెల్త్ ఇన్సూరెన్స్ కావాలి', 'मुझे अपने परिवार के लिए हेल्थ इंश्योरेंस चाहिए', 'ମୋ ପରିବାର ପାଇଁ ସ୍ୱାସ୍ଥ୍ୟ ବୀମା ଦରକାର')),
            ),
            _HistoryPreview(
              icon: Icons.work_outline_rounded,
              title: _tr('Computer operator job', 'కంప్యూటర్ ఆపరేటర్ ఉద్యోగం', 'कंप्यूटर ऑपरेटर नौकरी', 'କମ୍ପ୍ୟୁଟର ଅପରେଟର ଚାକିରି'),
              subtitle: _tr('Continue conversation', 'సంభాషణ కొనసాగించండి', 'बातचीत जारी रखें', 'କଥାବାର୍ତ୍ତା ଜାରି ରଖନ୍ତୁ'),
              onTap: () => _startFlow(_tr('I need a computer operator job', 'నాకు కంప్యూటర్ ఆపరేటర్ ఉద్యోగం కావాలి', 'मुझे कंप्यूटर ऑपरेटर की नौकरी चाहिए', 'ମୋତେ କମ୍ପ୍ୟୁଟର ଅପରେଟର ଚାକିରି ଦରକାର')),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFE9F7ED), Color(0xFFEAF1FF)]),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  const CircleAvatar(radius: 25, backgroundColor: Colors.white, child: Icon(Icons.explore_rounded, color: Color(0xFF1769FF))),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_tr('Explore ASKODOX', 'ASKODOXలో మరిన్ని చూడండి', 'ASKODOX एक्सप्लोर करें', 'ASKODOX ଅନ୍ୱେଷଣ କରନ୍ତୁ'), style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF14213D))),
                        const SizedBox(height: 3),
                        Text(
                          _tr(
                            'Jobs, services, rides and more — open only when you want shortcuts.',
                            'ఉద్యోగాలు, సేవలు, రైడ్లు మరియు మరిన్ని — అవసరమైనప్పుడు మాత్రమే షార్ట్‌కట్స్ తెరవండి.',
                            'नौकरियाँ, सेवाएँ, राइड और बहुत कुछ — जरूरत होने पर ही शॉर्टकट खोलें।',
                            'ଚାକିରି, ସେବା, ରାଇଡ୍ ଏବଂ ଅଧିକ — ଆବଶ୍ୟକ ହେଲେ ମାତ୍ର ଶର୍ଟକଟ୍ ଖୋଲନ୍ତୁ।',
                          ),
                          style: const TextStyle(color: Color(0xFF667085), height: 1.35),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => context.go('/search'), icon: const Icon(Icons.arrow_forward_rounded)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryPreview extends StatelessWidget {
  const _HistoryPreview({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        margin: const EdgeInsets.only(bottom: 10),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE5EAF2))),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(backgroundColor: const Color(0xFFEAF1FF), child: Icon(icon, color: const Color(0xFF1769FF))),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF14213D))),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        ),
      );
}