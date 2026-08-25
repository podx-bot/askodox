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

  void _startFlow(String text) {
    if (_telugu.hasMatch(text)) {
      ref.read(appSettingsProvider.notifier).setLocale(const Locale('te'));
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
    final isTe = settings.locale?.languageCode == 'te';
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE8F8ED),
                  child: Icon(Icons.language_rounded, color: Color(0xFF10A53A)),
                ),
                title: Text(isTe ? 'భాష' : 'Language', style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text(isTe
                    ? 'డివైస్ భాషను ఆటోగా అనుసరించవచ్చు. ఎప్పుడైనా మార్చుకోవచ్చు.'
                    : 'Auto follows your device. You can change it anytime.'),
              ),
              RadioListTile<String>(
                value: 'system',
                groupValue: selected,
                onChanged: (value) => Navigator.pop(context, value),
                title: Text(isTe ? 'ఆటో / డివైస్ భాష' : 'Auto / Device language'),
              ),
              RadioListTile<String>(
                value: 'en',
                groupValue: selected,
                onChanged: (value) => Navigator.pop(context, value),
                title: const Text('English'),
              ),
              RadioListTile<String>(
                value: 'te',
                groupValue: selected,
                onChanged: (value) => Navigator.pop(context, value),
                title: const Text('తెలుగు'),
              ),
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

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(appSettingsProvider).locale;
    final isTe = locale?.languageCode == 'te';
    final languageLabel = locale == null ? (isTe ? 'ఆటో' : 'Auto') : (isTe ? 'తెలుగు' : 'EN');

    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          tooltip: isTe ? 'మెను' : 'Menu',
          onPressed: () => context.go('/profile'),
          icon: const Icon(Icons.menu_rounded, color: Color(0xFF14213D)),
        ),
        title: const Text(
          'ASKODOX AI',
          style: TextStyle(color: Color(0xFF14213D), fontWeight: FontWeight.w900),
        ),
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
              isTe ? 'హాయ్! నేను ASKODOX AI' : 'Hi! I’m ASKODOX AI',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: Color(0xFF14213D)),
            ),
            const SizedBox(height: 7),
            Text(
              isTe ? 'మీకు కావాల్సింది చెప్పండి. నేను అర్థం చేసుకుని, అవసరమైనది మాత్రమే అడిగి, సరైన మ్యాచ్ కనుగొంటాను.' : 'Tell me what you need. I’ll understand it, clarify only what’s missing, and find the best match.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, height: 1.45, color: Color(0xFF667085)),
            ),
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFB8CCFF), width: 1.5),
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
                style: const TextStyle(color: Color(0xFF14213D), fontSize: 16),
                decoration: InputDecoration(
                  hintText: isTe ? 'మీకు ఏమి కావాలో చెప్పండి…' : 'Talk or type what you need…',
                  hintStyle: const TextStyle(color: Color(0xFF98A2B3)),
                  prefixIcon: const Icon(Icons.auto_awesome_rounded, color: Color(0xFF10A53A)),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const Key('askodoxMicButton'),
                        tooltip: isTe ? 'వాయిస్' : 'Voice',
                        onPressed: () => context.go('/discover/voice'),
                        icon: const Icon(Icons.mic_rounded, color: Color(0xFF10A53A)),
                      ),
                      IconButton(
                        key: const Key('askodoxSendButton'),
                        tooltip: isTe ? 'ASKODOXని అడగండి' : 'Ask ASKODOX',
                        onPressed: _submit,
                        icon: const CircleAvatar(
                          backgroundColor: Color(0xFF1769FF),
                          child: Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                    ],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isTe ? 'ఇటీవలి హిస్టరీ' : 'Recent history',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: Color(0xFF14213D)),
                ),
                TextButton(
                  onPressed: () => context.go('/watchlist'),
                  child: Text(isTe ? 'అన్నీ చూడండి' : 'See all'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _HistoryPreview(
              icon: Icons.shopping_bag_outlined,
              title: isTe ? 'దగ్గరలో చికెన్ కావాలి' : 'Chicken nearby',
              subtitle: isTe ? 'మ్యాచ్‌లు సిద్ధంగా ఉన్నాయి' : 'Matches ready',
              onTap: () => _startFlow(isTe ? 'నాకు దగ్గరలో చికెన్ కావాలి' : 'I want chicken nearby'),
            ),
            _HistoryPreview(
              icon: Icons.work_outline_rounded,
              title: isTe ? 'కంప్యూటర్ ఆపరేటర్ ఉద్యోగం' : 'Computer operator job',
              subtitle: isTe ? 'సంభాషణ కొనసాగించండి' : 'Continue conversation',
              onTap: () => _startFlow(isTe ? 'నాకు కంప్యూటర్ ఆపరేటర్ ఉద్యోగం కావాలి' : 'I need a computer operator job'),
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
                  const CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.explore_rounded, color: Color(0xFF1769FF)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isTe ? 'ASKODOXలో మరిన్ని చూడండి' : 'Explore ASKODOX', style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF14213D))),
                        const SizedBox(height: 3),
                        Text(
                          isTe ? 'ఉద్యోగాలు, సేవలు, రైడ్లు మరియు మరిన్ని — అవసరమైనప్పుడు మాత్రమే షార్ట్‌కట్స్ తెరవండి.' : 'Jobs, services, rides and more — open only when you want shortcuts.',
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE5EAF2)),
        ),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFEAF1FF),
            child: Icon(icon, color: const Color(0xFF1769FF)),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF14213D))),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        ),
      );
}
