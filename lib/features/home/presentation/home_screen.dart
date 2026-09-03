import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/providers/app_settings_provider.dart';
import '../../../services/vision_api_service.dart';
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
  final _picker = ImagePicker();
  XFile? _attachment;

  static final _telugu = RegExp(r'[\u0C00-\u0C7F]');
  static final _hindi = RegExp(r'[\u0900-\u097F]');
  static final _odia = RegExp(r'[\u0B00-\u0B7F]');

  String _lang() {
    final manual = ref.read(appSettingsProvider).locale?.languageCode;
    if (manual != null) return manual;
    final device = Localizations.localeOf(context).languageCode;
    return const {'en', 'te', 'hi', 'or'}.contains(device) ? device : 'en';
  }

  String _tr(String en, String te, String hi, String or) => switch (_lang()) {
        'te' => te,
        'hi' => hi,
        'or' => or,
        _ => en,
      };

  Future<void> _startFlow(String text) async {
    if (_telugu.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('te'));
    } else if (_hindi.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('hi'));
    } else if (_odia.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('or'));
    }
    final deal = ref.read(universalDealControllerProvider.notifier);
    deal.start(text);
    final attachment = _attachment;
    if (attachment != null) {
      deal.attachMedia(path: attachment.path, name: attachment.name);
    }
    final language = _lang();
    context.go('/search');

    if (attachment != null) {
      final analysis = await const VisionApiService().analyze(
        image: attachment,
        userText: text,
        language: language,
      );
      if (analysis != null) deal.mergeVisionAnalysis(analysis);
    }
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return _focusNode.requestFocus();
    _startFlow(text);
  }

  Future<void> _pickImage() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
      if (!mounted || picked == null) return;
      setState(() => _attachment = picked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_tr(
        'Could not open photos. Please try again.',
        'ఫోటోలు తెరవలేకపోయాం. మళ్లీ ప్రయత్నించండి.',
        'फ़ोटो नहीं खुल सके। फिर से कोशिश करें।',
        'ଫଟୋ ଖୋଲିହେଲା ନାହିଁ। ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।',
      ))));
    }
  }

  Future<void> _pickLanguage() async {
    final settings = ref.read(appSettingsProvider);
    final selected = settings.locale == null ? 'system' : settings.locale!.languageCode;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            leading: CircleAvatar(backgroundColor: Color(0xFFF0ECFF), child: Icon(Icons.language_rounded, color: _purple)),
            title: Text('ASKODOX Language', style: TextStyle(fontWeight: FontWeight.w900, color: _ink)),
            subtitle: Text('Auto follows your device. Change anytime.', style: TextStyle(color: _muted)),
          ),
          for (final item in const [
            ('system', 'Auto / Device language'),
            ('en', 'English'),
            ('hi', 'हिन्दी'),
            ('te', 'తెలుగు'),
            ('or', 'ଓଡ଼ିଆ'),
          ])
            RadioListTile<String>(
              value: item.$1,
              groupValue: selected,
              activeColor: _purple,
              onChanged: (value) => Navigator.pop(context, value),
              title: Text(item.$2, style: const TextStyle(color: _ink, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
    if (!mounted || choice == null) return;
    if (choice == 'system') {
      ref.read(appSettingsProvider.notifier).useSystemLocale();
    } else {
      ref.read(appSettingsProvider.notifier).setLocale(Locale(choice));
    }
  }

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
        leading: IconButton(onPressed: () => context.go('/profile'), icon: const Icon(Icons.menu_rounded, color: _ink)),
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
            Text(_tr('Good evening 👋', 'శుభ సాయంత్రం 👋', 'शुभ संध्या 👋', 'ଶୁଭ ସନ୍ଧ୍ୟା 👋'), style: const TextStyle(color: _ink, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            RichText(text: TextSpan(
              style: const TextStyle(fontSize: 30, height: 1.08, fontWeight: FontWeight.w900, color: _ink),
              children: [
                TextSpan(text: _tr('What can I\n', 'నేను ఏమి\n', 'मैं क्या\n', 'ମୁଁ କଣ\n')),
                TextSpan(text: _tr('help you get done?', 'మీకు చేసి పెట్టగలను?', 'आपके लिए कर सकता हूँ?', 'ଆପଣଙ୍କ ପାଇଁ କରିପାରିବି?'), style: const TextStyle(color: _purple)),
              ],
            )),
            const SizedBox(height: 18),
            const Center(child: _AskodoxOrb()),
            const SizedBox(height: 18),
            _AskField(
              controller: _controller,
              focusNode: _focusNode,
              hint: _tr('Ask anything…', 'ఏదైనా అడగండి…', 'कुछ भी पूछें…', 'ଯେକୌଣସି କଥା ପଚାରନ୍ତୁ…'),
              onSubmit: _submit,
              onVoice: () => context.go('/discover/voice'),
              onImage: _pickImage,
            ),
            if (_attachment case final attachment?) ...[
              const SizedBox(height: 10),
              _AttachmentChip(name: attachment.name, onRemove: () => setState(() => _attachment = null)),
            ],
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
              child: ListView(scrollDirection: Axis.horizontal, children: [
                _QuickCard(icon: Icons.shopping_bag_outlined, label: _tr('Chicken\nnear me', 'దగ్గరలో\nచికెన్', 'पास में\nचिकन', 'ନିକଟରେ\nଚିକେନ୍'), onTap: () => _startFlow('I need chicken near me')),
                _QuickCard(icon: Icons.work_outline_rounded, label: _tr('Computer\noperator job', 'కంప్యూటర్\nఆపరేటర్ ఉద్యోగం', 'कंप्यूटर\nऑपरेटर जॉब', 'କମ୍ପ୍ୟୁଟର\nଅପରେଟର ଜବ୍'), onTap: () => _startFlow('I need a computer operator job')),
                _QuickCard(icon: Icons.directions_car_outlined, label: _tr('Ride to\nHyderabad', 'హైదరాబాద్\nరైడ్', 'हैदराबाद\nराइड', 'ହାଇଦ୍ରାବାଦ\nରାଇଡ୍'), onTap: () => _startFlow('I need a ride to Hyderabad')),
                _QuickCard(icon: Icons.home_repair_service_outlined, label: _tr('Book a\nservice', 'సర్వీస్\nబుక్ చేయండి', 'सर्विस\nबुक करें', 'ସର୍ଭିସ୍\nବୁକ୍ କରନ୍ତୁ'), onTap: () => _startFlow('I need a local service')),
              ]),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 1,
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFEDE8FF),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.chat_bubble_outline_rounded), label: _tr('Chats', 'చాట్స్', 'चैट्स', 'ଚାଟ୍ସ')),
          NavigationDestination(icon: const Icon(Icons.auto_awesome_rounded, color: _purple), label: _tr('Ask', 'అడగండి', 'पूछें', 'ପଚାରନ୍ତୁ')),
          NavigationDestination(icon: const Icon(Icons.monitor_heart_outlined), label: _tr('Activity', 'యాక్టివిటీ', 'एक्टिविटी', 'କାର୍ଯ୍ୟକଳାପ')),
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
  const _AskField({required this.controller, required this.focusNode, required this.hint, required this.onSubmit, required this.onVoice, required this.onImage});
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final VoidCallback onSubmit;
  final VoidCallback onVoice;
  final VoidCallback onImage;

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
            prefixIcon: IconButton(
              key: const Key('askodoxMicButton'),
              tooltip: 'Voice',
              onPressed: onVoice,
              icon: const Icon(Icons.mic_none_rounded, color: _ink),
            ),
            suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                key: const Key('askodoxImageButton'),
                tooltip: 'Add image',
                onPressed: onImage,
                icon: const Icon(Icons.image_outlined, color: _ink),
              ),
              IconButton(
                key: const Key('askodoxSendButton'),
                tooltip: 'Send',
                onPressed: onSubmit,
                icon: const CircleAvatar(backgroundColor: _purple, child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20)),
              ),
            ]),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 17),
          ),
        ),
      );
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({required this.name, required this.onRemove});
  final String name;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Chip(
          key: const Key('askodoxAttachmentChip'),
          avatar: const Icon(Icons.image_outlined, color: _purple, size: 18),
          label: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(name.isEmpty ? 'Image attached' : name, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          deleteIcon: const Icon(Icons.close_rounded, size: 18),
          onDeleted: onRemove,
        ),
      );
}

class _AskodoxOrb extends StatelessWidget {
  const _AskodoxOrb();
  @override
  Widget build(BuildContext context) => Container(
        width: 112,
        height: 112,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [Color(0xFF0B183E), Color(0xFF28146F), Color(0xFF7A4DFF)]),
          boxShadow: [BoxShadow(color: Color(0x447A4DFF), blurRadius: 26, spreadRadius: 6), BoxShadow(color: Color(0x2920D9FF), blurRadius: 38, spreadRadius: 2)],
        ),
        child: const Stack(alignment: Alignment.center, children: [
          Icon(Icons.smart_toy_rounded, color: Colors.white, size: 52),
          Positioned(left: 35, top: 43, child: _Dot()),
          Positioned(right: 35, top: 43, child: _Dot()),
          Positioned(bottom: 25, child: Icon(Icons.keyboard_arrow_up_rounded, color: Color(0xFF3DE9FF), size: 20)),
        ]),
      );
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF3DE9FF)));
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action, required this.onTap});
  final String title;
  final String action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: Text(title, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w900))),
        TextButton(onPressed: onTap, child: Text(action, style: const TextStyle(color: _purple, fontWeight: FontWeight.w800))),
      ]);
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
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8E5F6))),
            child: Row(children: [
              const CircleAvatar(backgroundColor: Color(0xFFE8FFF5), child: Icon(Icons.auto_awesome_rounded, color: Color(0xFF18A66A))),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: _ink, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(subtitle, style: const TextStyle(color: _muted, fontSize: 12)),
              ])),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ]),
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
              Flexible(child: Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink, fontSize: 11, height: 1.1, fontWeight: FontWeight.w800))),
            ]),
          ),
        ),
      );
}
