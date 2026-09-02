import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../deal_brain/application/universal_deal_controller.dart';

const _ink = Color(0xFF111936);
const _muted = Color(0xFF6B7280);
const _purple = Color(0xFF7A4DFF);
const _soft = Color(0xFFF7F8FF);

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
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(0xFFF0ECFF),
                  child: Icon(Icons.language_rounded, color: _purple),
                ),
                title: Text('ASKODOX Language', style: TextStyle(fontWeight: FontWeight.w900, color: _ink)),
                subtitle: Text('Auto follows your device. Change anytime.', style: TextStyle(color: _muted)),
              ),
              _languageChoice(selected, 'system', 'Auto / Device language'),
              _languageChoice(selected, 'en', 'English'),
              _languageChoice(selected, 'hi', 'हिन्दी'),
              _languageChoice(selected, 'te', 'తెలుగు'),
              _languageChoice(selected, 'or', 'ଓଡ଼ିଆ'),
            ],
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
        activeColor: _purple,
        onChanged: (choice) => Navigator.pop(context, choice),
        title: Text(label, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
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
    final languageLabel = settings.locale == null
        ? 'Auto'
        : switch (settings.locale!.languageCode) {
            'te' => 'తెలుగు',
            'hi' => 'हिन्दी',
            'or' => 'ଓଡ଼ିଆ',
            _ => 'EN',
          };

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text('ASKODOX', style: TextStyle(color: _ink, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
        leading: IconButton(
          tooltip: _tr('Menu', 'మెను', 'मेनू', 'ମେନୁ'),
          onPressed: () => context.go('/profile'),
          icon: const Icon(Icons.menu_rounded, color: _ink),
        ),
        actions: [
          TextButton(
            key: const Key('askodoxLanguageButton'),
            onPressed: _pickLanguage,
            child: Text(languageLabel, style: const TextStyle(color: _purple, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
            Text(
              _tr('Good evening 👋', 'శుభ సాయంత్రం 👋', 'शुभ संध्या 👋', 'ଶୁଭ ସନ୍ଧ୍ୟା 👋'),
              style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 30, height: 1.08, fontWeight: FontWeight.w900, color: _ink),
                children: [
                  TextSpan(text: _tr('What can I\n', 'నేను ఏమి\n', 'मैं क्या\n', 'ମୁଁ କଣ\n')),
                  TextSpan(
                    text: _tr('help you get done?', 'మీకు చేసి పెట్టగలను?', 'आपके लिए कर सकता हूँ?', 'ଆପଣଙ୍କ ପାଇଁ କରିପାରିବି?'),
                    style: const TextStyle(color: _purple),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Center(child: _AskodoxOrb()),
            const SizedBox(height: 22),
            _AskField(
              controller: _controller,
              focusNode: _focusNode,
              hint: _tr('Ask anything…', 'ఏదైనా అడగండి…', 'कुछ भी पूछें…', 'ଯେକୌଣସି କଥା ପଚାରନ୍ତୁ…'),
              onSubmit: _submit,
              onVoice: () => context.go('/discover/voice'),
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: _tr('In Progress', 'ప్రస్తుతం జరుగుతున్నవి', 'चल रहा है', 'ଚାଲିଛି'),
              action: _tr('Activity', 'యాక్టివిటీ', 'एक्टिविटी', 'କାର୍ଯ୍ୟକଳାପ'),
              onTap: () => context.go('/activity'),
            ),
            const SizedBox(height: 10),
            _ProgressCard(
              title: _tr('ASKODOX is finding your best match', 'మీకు సరైన మ్యాచ్‌ను ASKODOX వెతుకుతోంది', 'ASKODOX आपका सही मैच ढूँढ रहा है', 'ASKODOX ଆପଣଙ୍କ ସର୍ବୋତ୍ତମ ମ୍ୟାଚ୍ ଖୋଜୁଛି'),
              subtitle: _tr('Live matching • Continue anytime', 'లైవ్ మ్యాచింగ్ • ఎప్పుడైనా కొనసాగించండి', 'लाइव मैचिंग • कभी भी जारी रखें', 'ଲାଇଭ୍ ମ୍ୟାଚିଂ • ଯେକୌଣସି ସମୟରେ ଜାରି ରଖନ୍ତୁ'),
              onTap: () => context.go('/search'),
            ),
            const SizedBox(height: 24),
            _SectionHeader(
              title: _tr('Continue your conversations', 'మీ సంభాషణలను కొనసాగించండి', 'अपनी बातचीत जारी रखें', 'ଆପଣଙ୍କ କଥୋପକଥନ ଜାରି ରଖନ୍ତୁ'),
              action: _tr('View all', 'అన్నీ చూడండి', 'सभी देखें', 'ସବୁ ଦେଖନ୍ତୁ'),
              onTap: () => context.go('/search'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 108,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _QuickCard(icon: Icons.shopping_bag_outlined, label: _tr('Chicken\nnear me', 'దగ్గరలో\nచికెన్', 'पास में\nचिकन', 'ନିକଟରେ\nଚିକେନ୍'), onTap: () => _startFlow('I need chicken near me')),
                  _QuickCard(icon: Icons.work_outline_rounded, label: _tr('Computer\noperator job', 'కంప్యూటర్\nఆపరేటర్ ఉద్యోగం', 'कंप्यूटर\nऑपरेटर जॉब', 'କମ୍ପ୍ୟୁଟର\nଅପରେଟର ଜବ୍'), onTap: () => _startFlow('I need a computer operator job')),
                  _QuickCard(icon: Icons.directions_car_outlined, label: _tr('Ride to\nHyderabad', 'హైదరాబాద్\nరైడ్', 'हैदराबाद\nराइड', 'ହାଇଦ୍ରାବାଦ\nରାଇଡ୍'), onTap: () => _startFlow('I need a ride to Hyderabad')),
                  _QuickCard(icon: Icons.home_repair_service_outlined, label: _tr('Book a\nservice', 'సర్వీస్\nబుక్ చేయండి', 'सर्विस\nबुक करें', 'ସର୍ଭିସ୍\nବୁକ୍ କରନ୍ତୁ'), onTap: () => _startFlow('I need a local service')),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _tr('One AI. Your local world.', 'ఒకే AI. మీ లోకల్ ప్రపంచం.', 'एक AI. आपकी लोकल दुनिया.', 'ଗୋଟିଏ AI. ଆପଣଙ୍କ ସ୍ଥାନୀୟ ଦୁନିଆ.'),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: _ink),
            ),
            const SizedBox(height: 12),
            const _CapabilityGrid(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFEDE8FF),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), label: 'Chats'),
          NavigationDestination(icon: Icon(Icons.auto_awesome_rounded, color: _purple), label: 'Ask'),
          NavigationDestination(icon: Icon(Icons.monitor_heart_outlined), label: 'Activity'),
        ],
        onDestinationSelected: (index) {
          if (index == 0) context.go('/search');
          if (index == 2) context.go('/activity');
        },
      ),
    );
  }
}

class _AskField extends StatelessWidget {
  const _AskField({required this.controller, required this.focusNode, required this.hint, required this.onSubmit, required this.onVoice});
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmit;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xFFC8B9FF), width: 1.4),
          boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 20, offset: Offset(0, 8))],
        ),
        child: TextField(
          key: const Key('askodoxAskField'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => onSubmit(),
          maxLines: 3,
          minLines: 1,
          style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
            prefixIcon: IconButton(key: const Key('askodoxMicButton'), onPressed: onVoice, icon: const Icon(Icons.mic_none_rounded, color: _ink)),
            suffixIcon: IconButton(
              key: const Key('askodoxSendButton'),
              onPressed: onSubmit,
              icon: const CircleAvatar(backgroundColor: _purple, child: Icon(Icons.add_rounded, color: Colors.white)),
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 17),
          ),
        ),
      );
}

class _AskodoxOrb extends StatelessWidget {
  const _AskodoxOrb();

  @override
  Widget build(BuildContext context) => Container(
        width: 132,
        height: 132,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color(0xFF0B183E), Color(0xFF28146F), Color(0xFF7A4DFF)]),
          boxShadow: [
            BoxShadow(color: Color(0x557A4DFF), blurRadius: 32, spreadRadius: 8),
            BoxShadow(color: Color(0x3320D9FF), blurRadius: 48, spreadRadius: 3),
          ],
        ),
        child: const Stack(
          alignment: Alignment.center,
          children: [
            Icon(Icons.smart_toy_rounded, color: Colors.white, size: 62),
            Positioned(left: 41, top: 51, child: _Dot()),
            Positioned(right: 41, top: 51, child: _Dot()),
            Positioned(bottom: 31, child: Icon(Icons.keyboard_arrow_up_rounded, color: Color(0xFF3DE9FF), size: 23)),
          ],
        ),
      );
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(width: 9, height: 9, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3DE9FF)));
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action, required this.onTap});
  final String title;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(child: Text(title, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w900))),
          TextButton(onPressed: onTap, child: Text(action, style: const TextStyle(color: _purple, fontWeight: FontWeight.w800))),
        ],
      );
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.title, required this.subtitle, required this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8E5F6)),
              boxShadow: const [BoxShadow(color: Color(0x0C000000), blurRadius: 16, offset: Offset(0, 5))],
            ),
            child: Row(
              children: [
                const CircleAvatar(backgroundColor: Color(0xFFE8FFF5), child: Icon(Icons.auto_awesome_rounded, color: Color(0xFF18A66A))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
                ])),
                const Icon(Icons.chevron_right_rounded, color: _muted),
              ],
            ),
          ),
        ),
      );
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 94,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE9E7F5))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircleAvatar(backgroundColor: Colors.white, child: Icon(icon, color: _purple, size: 21)),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _ink, fontSize: 11, height: 1.1, fontWeight: FontWeight.w800),
                ),
              ),
            ]),
          ),
        ),
      );
}

class _CapabilityGrid extends StatelessWidget {
  const _CapabilityGrid();
  @override
  Widget build(BuildContext context) => GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.65,
        children: const [
          _Capability(icon: Icons.shopping_bag_outlined, title: 'Buy & Local', subtitle: 'Products nearby'),
          _Capability(icon: Icons.work_outline_rounded, title: 'Jobs', subtitle: 'Skills & openings'),
          _Capability(icon: Icons.directions_car_outlined, title: 'Rides', subtitle: 'Travel & pooling'),
          _Capability(icon: Icons.insights_outlined, title: 'Business', subtitle: 'Sales & insights'),
        ],
      );
}

class _Capability extends StatelessWidget {
  const _Capability({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE9E7F5))),
        child: Row(children: [
          CircleAvatar(backgroundColor: Colors.white, child: Icon(icon, color: _purple, size: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
            Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _muted, fontSize: 11)),
          ])),
        ]),
      );
}
