import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../matching/data/universal_match_repository.dart';

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

/// Plays a result video INSIDE ASKODOX. Back returns to the same chat
/// position (the chat stays mounted underneath); the user can ask ASKODOX
/// about the video; "Open original" is only a secondary action.
class AskodoxVideoViewerScreen extends ConsumerWidget {
  const AskodoxVideoViewerScreen({super.key, required this.video, this.telugu = false});

  final UniversalMatch video;
  final bool telugu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = video.destinationUrl ?? '';
    final embed = askodoxVideoEmbedUri(url);
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
            child: KeyedSubtree(
              key: const Key('askodoxVideoEmbed'),
              child: ref.watch(askodoxVideoEmbedBuilderProvider)(embed),
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
                if (video.subtitle?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(video.subtitle!, style: const TextStyle(height: 1.35)),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const Key('askodoxVideoAsk'),
                  onPressed: () => Navigator.of(context).pop(askodoxVideoAskResult),
                  icon: const Icon(Icons.auto_awesome_rounded),
                  label: Text(telugu ? 'ఈ వీడియో గురించి ASKODOXని అడగండి' : 'Ask ASKODOX about this video'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('askodoxVideoOpenOriginal'),
                  onPressed: url.isEmpty
                      ? null
                      : () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
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
