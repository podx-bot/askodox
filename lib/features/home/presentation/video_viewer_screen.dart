import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../matching/data/universal_match_repository.dart';
import '../data/askodox_video_service.dart';

/// What the viewer returns when the user wants to discuss the video.
const askodoxVideoAskResult = 'ask';

/// Embeddable URL for a video page: YouTube watch/short/youtu.be links use
/// the privacy-friendly inline player; other hosts load their page.
Uri askodoxVideoEmbedUri(String url) {
  final uri = Uri.tryParse(url.trim()) ?? Uri();
  final host = uri.host.toLowerCase();
  String? id;
  if (host.endsWith('youtu.be')) {
    id = uri.pathSegments.isEmpty ? null : uri.pathSegments.first;
  } else if (host.endsWith('youtube.com')) {
    if (uri.pathSegments.isNotEmpty &&
        (uri.pathSegments.first == 'shorts' || uri.pathSegments.first == 'embed') &&
        uri.pathSegments.length > 1) {
      id = uri.pathSegments[1];
    } else {
      id = uri.queryParameters['v'];
    }
  }
  if (id != null && RegExp(r'^[A-Za-z0-9_-]{6,20}$').hasMatch(id)) {
    return Uri.parse('https://www.youtube-nocookie.com/embed/$id?autoplay=1&playsinline=1&rel=0');
  }
  return uri;
}

/// Builds the in-app player. Overridable so widget tests (which have no
/// platform WebView) can assert what would be embedded.
final askodoxVideoEmbedBuilderProvider = Provider<Widget Function(Uri uri)>(
  (ref) => (uri) => _WebVideoEmbed(uri: uri),
);

class _WebVideoEmbed extends StatefulWidget {
  const _WebVideoEmbed({required this.uri});
  final Uri uri;

  @override
  State<_WebVideoEmbed> createState() => _WebVideoEmbedState();
}

class _WebVideoEmbedState extends State<_WebVideoEmbed> {
  late final WebViewController _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(Colors.black)
    ..loadRequest(widget.uri);

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

/// A follow-up chosen in the viewer ("Find near me", "Show deals"...): the
/// viewer pops with `follow:<text>` and the chat sends that text in the SAME
/// conversation through the same discovery.
const askodoxVideoFollowUpPrefix = 'follow:';

/// The video's disclosure in the conversation language (the backend sends
/// the English wording; Telugu is shown for the ones ASKODOX writes).
String askodoxVideoDisclosure(String? disclosure, {bool telugu = false}) {
  final text = disclosure?.trim() ?? '';
  if (!telugu) return text;
  return switch (text) {
    "Creator's opinion -- not verified by ASKODOX" => 'క్రియేటర్ అభిప్రాయం -- ASKODOX ధృవీకరించలేదు',
    'Includes paid promotion (declared on YouTube)' => 'చెల్లింపు ప్రమోషన్ ఉంది (YouTubeలో ప్రకటించారు)',
    'From the business' => 'వ్యాపారం నుండి',
    "Creator's opinion" => 'క్రియేటర్ అభిప్రాయం',
    'Sponsored' => 'స్పాన్సర్డ్',
    'Affiliate -- ASKODOX may earn a commission' => 'అఫిలియేట్ -- ASKODOXకి కమీషన్ రావచ్చు',
    _ => text,
  };
}

String _serviceAsk(String service) =>
    service.trim().toLowerCase().endsWith('service') ? service.trim() : '${service.trim()} service';

/// Contextual next steps for a video: local / deals / compare / reviews and
/// used (products) or a local service (services). Pure, so it is testable.
List<({String action, String label, String ask, String event})> askodoxVideoNextSteps(UniversalMatch video,
    {bool telugu = false}) {
  final subject = video.relatedServices.isNotEmpty
      ? video.relatedServices.first
      : video.relatedProducts.isNotEmpty
          ? video.relatedProducts.first
          : video.title;
  final steps = <({String action, String label, String ask, String event})>[
    (action: 'find_local', label: telugu ? 'దగ్గరలో కనుగొనండి' : 'Find near me', ask: '$subject near me',
     event: 'video_local_search'),
    if (video.relatedServices.isNotEmpty)
      (action: 'local_service', label: telugu ? 'స్థానిక సేవ' : 'Book a local service',
       ask: '${_serviceAsk(video.relatedServices.first)} near me', event: 'video_service_click'),
    (action: 'deals', label: telugu ? 'డీల్స్ చూపించండి' : 'Show deals', ask: '$subject offers',
     event: 'video_product_click'),
    (action: 'compare', label: telugu ? 'పోల్చండి' : 'Compare', ask: 'Compare $subject with alternatives',
     event: 'video_product_click'),
    if (video.relatedServices.isEmpty)
      (action: 'used', label: telugu ? 'వాడినది / తక్కువ ధర' : 'Used / cheaper', ask: 'used $subject',
       event: 'video_product_click'),
    (action: 'reviews', label: telugu ? 'రివ్యూలు' : 'More reviews', ask: '$subject reviews',
     event: 'video_product_click'),
  ];
  return steps;
}

/// Plays a result video INSIDE ASKODOX where the platform offers an
/// official embed; otherwise it says so and opens the video in its own app
/// / web page. Back returns to the same chat position (the chat stays
/// mounted underneath); the user can ask ASKODOX about the video or pick a
/// next step, both in the same conversation.
class AskodoxVideoViewerScreen extends ConsumerStatefulWidget {
  const AskodoxVideoViewerScreen({super.key, required this.video, this.telugu = false});

  final UniversalMatch video;
  final bool telugu;

  @override
  ConsumerState<AskodoxVideoViewerScreen> createState() => _AskodoxVideoViewerScreenState();
}

class _AskodoxVideoViewerScreenState extends ConsumerState<AskodoxVideoViewerScreen> {
  UniversalMatch get video => widget.video;
  bool get telugu => widget.telugu;

  /// Reviewed (Command Center) videos carry the backend's embed decision;
  /// web-found videos keep the YouTube-or-page behaviour.
  Uri? get _embed {
    if (video.videoId != null) {
      final embed = video.embedUrl?.trim() ?? '';
      return embed.isEmpty ? null : Uri.tryParse(embed);
    }
    final url = video.destinationUrl ?? '';
    return url.isEmpty ? null : askodoxVideoEmbedUri(url);
  }

  @override
  void initState() {
    super.initState();
    final service = ref.read(askodoxVideoServiceProvider);
    service.track('video_open', video.videoId);
    if (_embed != null) service.track('video_watch_start', video.videoId);
  }

  void _follow(({String action, String label, String ask, String event}) step) {
    ref.read(askodoxVideoServiceProvider).track(step.event, video.videoId);
    Navigator.of(context).pop('$askodoxVideoFollowUpPrefix${step.ask}');
  }

  Future<void> _openOriginal() async {
    final url = video.destinationUrl ?? '';
    if (url.isEmpty) return;
    if (video.affiliate) ref.read(askodoxVideoServiceProvider).track('video_affiliate_click', video.videoId);
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  String get _platformName {
    final p = (video.videoPlatform ?? video.sourceName ?? '').trim();
    return p.isEmpty ? (telugu ? 'యాప్' : 'its app') : p[0].toUpperCase() + p.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final url = video.destinationUrl ?? '';
    final embed = _embed;
    final label = video.paidPlacementLabel;
    final disclosure = askodoxVideoDisclosure(video.disclosure, telugu: telugu);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: Column(children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: embed != null
                ? KeyedSubtree(
                    key: const Key('askodoxVideoEmbed'),
                    child: ref.watch(askodoxVideoEmbedBuilderProvider)(embed),
                  )
                : Container(
                    key: const Key('askodoxVideoNoEmbed'),
                    color: const Color(0xFF10204A),
                    padding: const EdgeInsets.all(20),
                    alignment: Alignment.center,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.smart_display_rounded, color: Colors.white70, size: 42),
                      const SizedBox(height: 10),
                      Text(
                        telugu
                            ? 'ఈ వీడియోను ఇక్కడ ప్లే చేయడానికి $_platformName అనుమతించదు.'
                            : '$_platformName does not allow playing this video inside ASKODOX.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      FilledButton.tonalIcon(
                        key: const Key('askodoxVideoOpenInApp'),
                        onPressed: url.isEmpty ? null : _openOriginal,
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: Text(telugu ? '$_platformNameలో చూడండి' : 'Watch in $_platformName'),
                      ),
                    ]),
                  ),
          ),
          Expanded(
            child: ColoredBox(
              color: Colors.white,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Text(video.title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF10204A))),
                const SizedBox(height: 6),
                Text(
                  [
                    if (video.sourceName?.isNotEmpty == true) video.sourceName!,
                    if (video.duration?.isNotEmpty == true) video.duration!,
                  ].join(' • '),
                  style: const TextStyle(color: Color(0xFF667085), fontWeight: FontWeight.w700),
                ),
                if (label != null || disclosure.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (label != null)
                      Container(
                        key: const Key('askodoxVideoPaidLabel'),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(6)),
                        child: Text(label,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF9A5B00))),
                      ),
                    if (disclosure.isNotEmpty)
                      Text(disclosure,
                          key: const Key('askodoxVideoDisclosure'),
                          style: const TextStyle(fontSize: 12, color: Color(0xFF667085))),
                  ]),
                ],
                if (video.subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(video.subtitle!, style: const TextStyle(height: 1.35)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('askodoxVideoAsk'),
                  // The ask itself is recorded once, by the backend, when
                  // the chat asks /api/videos/{id}/explain.
                  onPressed: () => Navigator.of(context).pop(askodoxVideoAskResult),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(telugu ? 'ఈ వీడియో గురించి ASKODOXని అడగండి' : 'Ask ASKODOX about this video'),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final step in askodoxVideoNextSteps(video, telugu: telugu))
                    ActionChip(
                      key: Key('askodoxVideoNext_${step.action}'),
                      label: Text(step.label),
                      onPressed: () => _follow(step),
                    ),
                ]),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('askodoxVideoOpenOriginal'),
                  onPressed: url.isEmpty ? null : _openOriginal,
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: Text(telugu ? 'అసలు పేజీ తెరవండి' : 'Open original'),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
