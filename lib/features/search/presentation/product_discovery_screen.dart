import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../catalog/presentation/widgets/product_card.dart';
import '../../catalog/presentation/widgets/product_request_actions.dart';
import '../application/product_discovery_controller.dart';
import '../domain/search_models.dart';

class ProductDiscoveryScreen extends ConsumerStatefulWidget {
  const ProductDiscoveryScreen({required this.mode, super.key});
  final SearchIntentType mode;
  @override
  ConsumerState<ProductDiscoveryScreen> createState() => _ProductDiscoveryScreenState();
}

class _ProductDiscoveryScreenState extends ConsumerState<ProductDiscoveryScreen> {
  final barcode = TextEditingController();
  @override
  void dispose() {
    barcode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(productDiscoveryControllerProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF050713),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(_title(widget.mode)),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF070A1C), Color(0xFF100624)],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.mode != SearchIntentType.voice) _hero(context),
            if (widget.mode != SearchIntentType.voice) const SizedBox(height: 16),
            if (widget.mode == SearchIntentType.barcode) ..._barcode(state),
            if (widget.mode == SearchIntentType.ocr) ..._ocr(state),
            if (widget.mode == SearchIntentType.image) ..._image(state),
            if (widget.mode == SearchIntentType.voice) ..._voice(state),
            if (state.matches.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Smart matches', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) => GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: c.maxWidth > 800 ? 4 : 2,
                    childAspectRatio: .68,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: state.matches.length,
                  itemBuilder: (_, i) => Column(
                    children: [
                      Expanded(child: ProductCard(product: state.matches[i].product)),
                      Text(
                        '${state.matches[i].confidence.label} • ${(state.matches[i].confidence.score * 100).round()}% • ${state.matches[i].reason}',
                        maxLines: 2,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(_icon(widget.mode), size: 42, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  _description(widget.mode),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ],
          ),
        ),
      );

  List<Widget> _barcode(DiscoveryState s) => [
        TextField(
          controller: barcode,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Enter barcode number',
            prefixIcon: Icon(Icons.numbers),
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: () => ref.read(productDiscoveryControllerProvider.notifier).scan(barcode.text),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Find product'),
        ),
        if (s.barcodeResult != null)
          ListTile(
            leading: Icon(
              s.barcodeResult!.state == BarcodeMatchState.found
                  ? Icons.check_circle
                  : Icons.info,
            ),
            title: Text('Barcode: ${s.barcodeResult!.state.name}'),
            subtitle: Text('${s.barcodeResult!.matches.length} match(es)'),
          ),
      ];

  List<Widget> _ocr(DiscoveryState s) => [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Camera OCR is being connected to the live request pipeline. Use text or voice now.',
            ),
          ),
        ),
        if (s.ocrResult != null)
          Card(
            child: ListTile(
              title: const Text('Extracted text'),
              subtitle: Text(s.ocrResult!.extractedText),
              trailing: Text(s.ocrResult!.source),
            ),
          ),
        if (s.ocrResult != null && s.ocrResult!.matches.isEmpty)
          ...[const ProductRequestActions(compact: true)],
      ];

  List<Widget> _image(DiscoveryState s) => [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Image understanding is being connected to the live request pipeline. Use text or voice now.',
            ),
          ),
        ),
      ];

  List<Widget> _voice(DiscoveryState s) => [
        _VoiceAssistantCard(state: s.voiceState, result: s.voiceResult),
        const SizedBox(height: 18),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(58),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
          onPressed: s.voiceState == VoiceSearchState.listening ||
                  s.voiceState == VoiceSearchState.processing
              ? null
              : () => ref.read(productDiscoveryControllerProvider.notifier).startVoice(),
          icon: const Icon(Icons.mic_rounded),
          label: Text(
            s.voiceState == VoiceSearchState.listening
                ? 'Listening…'
                : s.voiceState == VoiceSearchState.processing
                    ? 'ASKODOX is understanding…'
                    : 'Talk to ASKODOX',
          ),
        ),
        const SizedBox(height: 14),
        Text(
          s.voiceResult == null
              ? 'Speak naturally. Text and voice use the same ASKODOX request brain.'
              : 'You said: ${s.voiceResult}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70),
        ),
      ];

  String _description(SearchIntentType mode) => switch (mode) {
        SearchIntentType.voice =>
          'Speak naturally. ASKODOX captures the same requirement as text and continues the same matching flow.',
        SearchIntentType.barcode => 'Enter a barcode to look for a matching live listing.',
        SearchIntentType.ocr => 'Read useful request details from a camera or image.',
        SearchIntentType.image => 'Understand an item or requirement from an image.',
        _ => 'Use the fastest input for your ASKODOX request.',
      };

  String _title(SearchIntentType mode) => switch (mode) {
        SearchIntentType.barcode => 'Barcode search',
        SearchIntentType.ocr => 'OCR matching',
        SearchIntentType.image => 'Image search',
        SearchIntentType.voice => 'ASKODOX Voice',
        _ => 'Smart search',
      };

  IconData _icon(SearchIntentType mode) => switch (mode) {
        SearchIntentType.barcode => Icons.qr_code_scanner,
        SearchIntentType.ocr => Icons.document_scanner_outlined,
        SearchIntentType.image => Icons.image_search,
        SearchIntentType.voice => Icons.mic,
        _ => Icons.auto_awesome,
      };
}

class _VoiceAssistantCard extends StatelessWidget {
  const _VoiceAssistantCard({required this.state, required this.result});

  final VoiceSearchState state;
  final String? result;

  String get label => switch (state) {
        VoiceSearchState.listening => 'Listening',
        VoiceSearchState.processing => 'Thinking & Understanding',
        VoiceSearchState.result => 'Understood',
        _ => 'Ready',
      };

  IconData get stateIcon => switch (state) {
        VoiceSearchState.listening => Icons.mic_rounded,
        VoiceSearchState.processing => Icons.psychology_alt_rounded,
        VoiceSearchState.result => Icons.check_rounded,
        _ => Icons.auto_awesome_rounded,
      };

  Color get accent => switch (state) {
        VoiceSearchState.listening => const Color(0xFF2C9CFF),
        VoiceSearchState.processing => const Color(0xFF9C4DFF),
        VoiceSearchState.result => const Color(0xFF44D7C5),
        _ => const Color(0xFF7A62FF),
      };

  @override
  Widget build(BuildContext context) {
    final active = state == VoiceSearchState.listening ||
        state == VoiceSearchState.processing;
    return Column(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Text(
            label,
            key: ValueKey(state),
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TweenAnimationBuilder<double>(
          key: ValueKey(state),
          duration: const Duration(milliseconds: 800),
          tween: Tween(begin: .94, end: active ? 1.04 : 1),
          curve: Curves.easeInOut,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            child: child,
          ),
          child: Container(
            width: 238,
            height: 238,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [accent, const Color(0xFF673BFF)],
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: .45),
                  blurRadius: active ? 50 : 32,
                  spreadRadius: active ? 7 : 3,
                ),
              ],
            ),
            padding: const EdgeInsets.all(9),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF080B19),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const _MiniRobot(),
                  Positioned(
                    bottom: 20,
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: accent,
                        boxShadow: [
                          BoxShadow(color: accent, blurRadius: 16),
                        ],
                      ),
                      child: Icon(stateIcon, color: Colors.white, size: 28),
                    ),
                  ),
                  if (state == VoiceSearchState.listening) ...[
                    const Positioned(left: 12, child: _SideWave()),
                    const Positioned(right: 12, child: _SideWave()),
                  ],
                  if (state == VoiceSearchState.processing)
                    const Positioned(
                      right: 23,
                      top: 34,
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: Color(0xFFBCA7FF),
                        size: 42,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'ASKODOX AI',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.8,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          result == null ? 'Ask Anything. Get It Done.' : 'Got it. Continuing your request.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFC6A8FF),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
      ],
    );
  }
}

class _MiniRobot extends StatelessWidget {
  const _MiniRobot();

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 5, height: 16, color: const Color(0xFF8093E8)),
          Transform.translate(
            offset: const Offset(0, -20),
            child: Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(
                color: Color(0xFF43A8FF),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Container(
            width: 128,
            height: 88,
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE9ECFB), Color(0xFF9BA8E1)],
              ),
              borderRadius: BorderRadius.circular(38),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF050817),
                borderRadius: BorderRadius.circular(29),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Icon(Icons.circle, size: 14, color: Color(0xFF47D9FF)),
                  Icon(Icons.circle, size: 14, color: Color(0xFF47D9FF)),
                ],
              ),
            ),
          ),
          Container(
            width: 78,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFE2E6FA), Color(0xFF98A4DD)],
              ),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
              border: Border.all(color: Colors.white70),
            ),
          ),
        ],
      );
}

class _SideWave extends StatelessWidget {
  const _SideWave();

  @override
  Widget build(BuildContext context) => Row(
        children: [
          for (final h in const [16.0, 30.0, 44.0, 30.0, 16.0])
            Container(
              width: 3,
              height: h,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: const Color(0xFF39A8FF),
                borderRadius: BorderRadius.circular(5),
              ),
            ),
        ],
      );
}

class DiscoveryTools extends StatelessWidget {
  const DiscoveryTools({super.key});
  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _button(context, 'Barcode', Icons.qr_code_scanner, 'barcode'),
          _button(context, 'OCR', Icons.document_scanner_outlined, 'ocr'),
          _button(context, 'Image', Icons.image_search, 'image'),
          _button(context, 'Voice', Icons.mic_none, 'voice'),
        ],
      );
  Widget _button(BuildContext c, String text, IconData icon, String route) =>
      ActionChip(
        avatar: Icon(icon),
        label: Text(text),
        onPressed: () => c.push('/discover/$route'),
      );
}
