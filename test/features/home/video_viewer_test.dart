import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/home/data/askodox_video_service.dart';
import 'package:podx/features/home/presentation/video_viewer_screen.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records every call; answers explain with a canned backend reply.
class _RecordingApi implements ApiClient {
  final posts = <(String, Object?)>[];

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts.add((path, body));
    if (path.endsWith('/explain')) {
      return ApiSuccess(<String, Object?>{
        'video_id': 'vid_1',
        'analyzed': false,
        'answer': "I haven't analyzed what is said in this video.",
        'from_source': ['Tata Nexon EV review'],
        'relationship': 'creator',
        'relationship_label': "Creator's opinion",
        'creator': 'Example Auto Reviews',
        'next': [
          {'action': 'find_local', 'label': 'Find near me', 'ask': 'Tata Nexon EV near me'},
        ],
      } as T);
    }
    return ApiSuccess(<String, Object?>{'recorded': true} as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(<String, Object?>{} as T);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      post<T>(path, body: body);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      post<T>(path, body: body);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) =>
      get<T>(path);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(Uri.parse('mock://$fileName'));

  List<String> get trackedEvents => [
        for (final (path, body) in posts)
          if (path == '/api/track') '${(body as Map)['event']}',
      ];
}

UniversalMatch _video(Map<String, Object?> extra) => UniversalMatch.fromJson({
      'id': 'video-vid_1',
      'video_id': 'vid_1',
      'title': 'Tata Nexon EV review',
      'source': 'video',
      'match_source': 'video',
      'segment': 'video',
      'destination_url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'embed_url': 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0',
      'platform': 'youtube',
      'products': ['Tata Nexon EV'],
      ...extra,
    });

Future<(_RecordingApi, List<Uri>, List<String?>)> _pump(WidgetTester tester, UniversalMatch video,
    {bool telugu = false}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final api = _RecordingApi();
  final embedded = <Uri>[];
  final popped = <String?>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(api),
      askodoxVideoEmbedBuilderProvider.overrideWithValue((uri) {
        embedded.add(uri);
        return const ColoredBox(color: Colors.black);
      }),
    ],
    child: MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open'),
              onPressed: () async {
                popped.add(await Navigator.of(context).push<String>(MaterialPageRoute(
                  builder: (_) => AskodoxVideoViewerScreen(video: video, telugu: telugu),
                )));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return (api, embedded, popped);
}

void main() {
  test('reviewed video fields round-trip (History restore)', () {
    final video = _video({'relationship': 'affiliate', 'affiliate': true, 'analyzed': true,
      'services': ['EV servicing'], 'disclosure': 'Affiliate -- ASKODOX may earn a commission'});
    final again = UniversalMatch.fromJson(video.toJson());
    expect(again.videoId, 'vid_1');
    expect(again.embedUrl, startsWith('https://www.youtube-nocookie.com/embed/'));
    expect(again.relationship, 'affiliate');
    expect(again.videoAnalyzed, isTrue);
    expect(again.relatedServices, ['EV servicing']);
    expect(again.paidPlacementLabel, 'Sponsored');
  });

  test('merchant offer on a seller result shows as the offer line', () {
    final match = UniversalMatch.fromJson({
      'id': '7', 'title': 'TV', 'match_source': 'registered',
      'merchant_offer': {'id': 'mof_1', 'summary': '₹100 off', 'claim_path': '/api/merchant-offers/mof_1/claim'},
    });
    expect(match.offerTitle, '₹100 off');
    expect(match.merchantOffer?['claim_path'], '/api/merchant-offers/mof_1/claim');
  });

  test('next steps: products get used/cheaper, services get a local service', () {
    final product = askodoxVideoNextSteps(_video({})).map((s) => s.action).toList();
    expect(product, ['find_local', 'deals', 'compare', 'used', 'reviews']);
    final service = askodoxVideoNextSteps(_video({'products': [], 'services': ['AC repair']}));
    expect(service.map((s) => s.action), contains('local_service'));
    expect(service.firstWhere((s) => s.action == 'local_service').ask, 'AC repair service near me');
    final te = askodoxVideoNextSteps(_video({}), telugu: true);
    expect(te.first.label, 'దగ్గరలో కనుగొనండి');
  });

  testWidgets('official embed plays in-app and open/watch are tracked', (tester) async {
    final (api, embedded, _) = await _pump(tester, _video({}));
    expect(embedded.single.toString(), 'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0');
    expect(find.byKey(const Key('askodoxVideoNoEmbed')), findsNothing);
    expect(api.trackedEvents, ['video_open', 'video_watch_start']);
    expect(find.byKey(const Key('askodoxVideoPaidLabel')), findsNothing, reason: 'organic: no label');
  });

  testWidgets('no official embed: honest message and open in its app', (tester) async {
    final (api, embedded, _) = await _pump(tester, _video({
      'platform': 'instagram', 'embed_url': null, 'destination_url': 'https://www.instagram.com/reel/Cexample/'}));
    expect(embedded, isEmpty, reason: 'never loads a page that forbids embedding');
    expect(find.textContaining('Instagram does not allow playing this video inside ASKODOX'), findsOneWidget);
    expect(find.byKey(const Key('askodoxVideoOpenInApp')), findsOneWidget);
    expect(api.trackedEvents, ['video_open']);
  });

  testWidgets('sponsored / affiliate videos show their disclosure', (tester) async {
    await _pump(tester, _video({'relationship': 'affiliate', 'affiliate': true,
      'disclosure': 'Affiliate -- ASKODOX may earn a commission'}));
    expect(find.byKey(const Key('askodoxVideoPaidLabel')), findsOneWidget);
    expect(find.text('Affiliate -- ASKODOX may earn a commission'), findsOneWidget);
  });

  testWidgets('a next step returns to the same chat with the follow-up and is tracked', (tester) async {
    final (api, _, popped) = await _pump(tester, _video({}));
    await tester.ensureVisible(find.byKey(const Key('askodoxVideoNext_find_local')));
    await tester.tap(find.byKey(const Key('askodoxVideoNext_find_local')));
    await tester.pumpAndSettle();
    expect(popped.single, '${askodoxVideoFollowUpPrefix}Tata Nexon EV near me');
    expect(api.trackedEvents.last, 'video_local_search');
  });

  testWidgets('Ask ASKODOX returns to chat and is tracked', (tester) async {
    final (api, _, popped) = await _pump(tester, _video({}));
    await tester.ensureVisible(find.byKey(const Key('askodoxVideoAsk')));
    await tester.tap(find.byKey(const Key('askodoxVideoAsk')));
    await tester.pumpAndSettle();
    expect(popped.single, askodoxVideoAskResult);
    expect(api.trackedEvents.last, 'video_ask');
  });

  test('explanation grounding never lets the assistant claim unanalyzed content', () async {
    final api = _RecordingApi();
    final explanation = await AskodoxVideoService(api).explain('vid_1', question: 'range?');
    expect(explanation, isNotNull);
    final context = explanation!.groundingContext();
    expect(context, contains('NOT analyzed'));
    expect(context, contains("Creator's opinion"));
    expect(context, contains('never invent'));
    expect(api.posts.single.$1, '/api/videos/vid_1/explain');
  });

  test('tracking ignores unknown events and rows without a video id', () {
    final api = _RecordingApi();
    final service = AskodoxVideoService(api);
    service.track('commission', 'vid_1');
    service.track('video_open', null);
    service.track('video_open', 'vid_1', category: 'tv');
    expect(api.trackedEvents, ['video_open']);
  });

  // Render evidence (opt-in, like the Home renders):
  // ASKODOX_RENDER=1 flutter test --update-goldens test/features/home/video_viewer_test.dart
  testWidgets('Video render: in-app embed with disclosure, no-embed fallback',
      skip: !Platform.environment.containsKey('ASKODOX_RENDER'), (tester) async {
    Future<void> font(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final f in files) {
        loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
      }
      await loader.load();
    }

    const fonts = '/root/sdk/flutter/bin/cache/artifacts/material_fonts';
    await tester.runAsync(() async {
      await font('Roboto', ['$fonts/Roboto-Regular.ttf', '$fonts/Roboto-Medium.ttf', '$fonts/Roboto-Bold.ttf',
          '$fonts/Roboto-Black.ttf']);
      await font('MaterialIcons', ['$fonts/MaterialIcons-Regular.otf']);
    });
    Future<void> render(UniversalMatch video, String name) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_RecordingApi()),
          // No platform WebView in tests: a frame naming what would play.
          askodoxVideoEmbedBuilderProvider.overrideWithValue((uri) => ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('Official embed\n${uri.host}${uri.path}',
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                  ),
                ),
              )),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
          home: AskodoxVideoViewerScreen(video: video),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('renders/$name.png'));
    }

    await render(
        _video({
          'title': 'Samsung 43 inch Crystal 4K TV - honest review',
          'source_name': 'Example Tech Telugu',
          'duration': '09:41',
          'relationship': 'affiliate',
          'affiliate': true,
          'disclosure': 'Affiliate -- ASKODOX may earn a commission',
          'subtitle': 'Picture, sound and smart features after one month of use.',
          'products': ['Samsung 43 inch TV'],
        }),
        '07_video_embed_affiliate');
    await render(
        _video({
          'title': 'AC gas refill - what a good technician checks',
          'platform': 'instagram',
          'embed_url': null,
          'destination_url': 'https://www.instagram.com/reel/Cexample/',
          'source_name': 'Sri Sai Cooling (business)',
          'relationship': 'merchant',
          'disclosure': 'From the business',
          'products': [],
          'services': ['AC repair'],
        }),
        '08_video_no_embed_service');
  });
}
