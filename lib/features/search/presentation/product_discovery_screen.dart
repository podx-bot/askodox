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
      appBar: AppBar(title: Text(_title(widget.mode))),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _hero(context),
          const SizedBox(height: 16),
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
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: c.maxWidth > 800 ? 4 : 2, childAspectRatio: .68, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: state.matches.length,
                itemBuilder: (_, i) => Column(children: [Expanded(child: ProductCard(product: state.matches[i].product)), Text('${state.matches[i].confidence.label} • ${(state.matches[i].confidence.score * 100).round()}% • ${state.matches[i].reason}', maxLines: 2, textAlign: TextAlign.center)]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Icon(_icon(widget.mode), size: 42, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(child: Text(_description(widget.mode), style: Theme.of(context).textTheme.bodyLarge)),
          ]),
        ),
      );

  List<Widget> _barcode(DiscoveryState s) => [
        TextField(controller: barcode, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Enter barcode number', prefixIcon: Icon(Icons.numbers))),
        const SizedBox(height: 10),
        FilledButton.icon(onPressed: () => ref.read(productDiscoveryControllerProvider.notifier).scan(barcode.text), icon: const Icon(Icons.qr_code_scanner), label: const Text('Find product')),
        if (s.barcodeResult != null) ListTile(leading: Icon(s.barcodeResult!.state == BarcodeMatchState.found ? Icons.check_circle : Icons.info), title: Text('Barcode: ${s.barcodeResult!.state.name}'), subtitle: Text('${s.barcodeResult!.matches.length} match(es)')),
      ];

  List<Widget> _ocr(DiscoveryState s) => [
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Camera OCR is being connected to the live product pipeline. Use text or voice search now.'))),
        if (s.ocrResult != null) Card(child: ListTile(title: const Text('Extracted text'), subtitle: Text(s.ocrResult!.extractedText), trailing: Text(s.ocrResult!.source))),
        if (s.ocrResult != null && s.ocrResult!.matches.isEmpty) ...[const ProductRequestActions(compact: true)],
      ];

  List<Widget> _image(DiscoveryState s) => [
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Image matching is being connected to the live product pipeline. Use text or voice search now.'))),
      ];

  List<Widget> _voice(DiscoveryState s) => [
        FilledButton.icon(
          onPressed: s.voiceState == VoiceSearchState.listening || s.voiceState == VoiceSearchState.processing ? null : () => ref.read(productDiscoveryControllerProvider.notifier).startVoice(),
          icon: const Icon(Icons.mic),
          label: Text(s.voiceState == VoiceSearchState.listening ? 'Listening…' : s.voiceState == VoiceSearchState.processing ? 'Processing…' : 'Start voice search'),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: Icon(s.voiceState == VoiceSearchState.result ? Icons.check_circle_outline : Icons.graphic_eq),
          title: Text('State: ${s.voiceState.name}'),
          subtitle: s.voiceResult == null ? const Text('Speak naturally. ASKODOX will use your words as the search request.') : Text('You said: ${s.voiceResult}'),
        ),
      ];

  String _description(SearchIntentType mode) => switch (mode) {
        SearchIntentType.voice => 'Speak what you need. ASKODOX will capture your request and continue the same search flow.',
        SearchIntentType.barcode => 'Enter a product barcode to look for a matching live listing.',
        SearchIntentType.ocr => 'Read product text from a camera or image.',
        SearchIntentType.image => 'Find visually similar products from an image.',
        _ => 'Search ASKODOX using the fastest input for you.',
      };

  String _title(SearchIntentType mode) => switch (mode) {SearchIntentType.barcode => 'Barcode search', SearchIntentType.ocr => 'OCR product matching', SearchIntentType.image => 'Image search', SearchIntentType.voice => 'Voice search', _ => 'Smart search'};
  IconData _icon(SearchIntentType mode) => switch (mode) {SearchIntentType.barcode => Icons.qr_code_scanner, SearchIntentType.ocr => Icons.document_scanner_outlined, SearchIntentType.image => Icons.image_search, SearchIntentType.voice => Icons.mic, _ => Icons.auto_awesome};
}

class DiscoveryTools extends StatelessWidget {
  const DiscoveryTools({super.key});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [_button(context, 'Barcode', Icons.qr_code_scanner, 'barcode'), _button(context, 'OCR', Icons.document_scanner_outlined, 'ocr'), _button(context, 'Image', Icons.image_search, 'image'), _button(context, 'Voice', Icons.mic_none, 'voice')]);
  Widget _button(BuildContext c, String text, IconData icon, String route) => ActionChip(avatar: Icon(icon), label: Text(text), onPressed: () => c.push('/discover/$route'));
}
