import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/home/data/askodox_video_service.dart';
import 'package:podx/features/home/domain/chat_result_policy.dart';
import 'package:podx/features/home/presentation/video_study_panel.dart';
import 'package:podx/features/home/presentation/video_viewer_screen.dart';
import 'package:podx/features/matching/data/universal_match_repository.dart';
import 'package:podx/services/chat_attachment_service.dart';

const _facts = [
  {'key': 'make', 'label': 'Make', 'value': 'Toyota', 'basis': 'confirmed_from_video', 'timestamp': '0:03',
   'evidence': 'badge'},
  {'key': 'model', 'label': 'Model', 'value': 'Innova Crysta', 'basis': 'seller_claim', 'timestamp': '0:05',
   'evidence': 'said'},
  {'key': 'year', 'label': 'Year', 'value': '2016', 'basis': 'seller_claim', 'timestamp': '0:20', 'evidence': 'said'},
  {'key': 'asking_price', 'label': 'Asking price', 'value': '₹12.5 lakh', 'basis': 'seller_claim',
   'timestamp': '1:42', 'evidence': 'పన్నెండున్నర లక్షలు'},
];

/// A backend that serves the Video Study endpoints like production.
class _StudyApi implements ApiClient {
  _StudyApi({this.studyStatus = 'ready', this.notFound = const {}});

  /// What POST /study returns: ready | unavailable.
  final String studyStatus;

  /// Questions the video cannot answer.
  final Set<String> notFound;
  final calls = <(String, String, Object?)>[];
  bool studied = false;

  Map<String, Object?> _study(String lang) => {
        'ref': 'yt_car', 'status': studyStatus, 'category': 'vehicle', 'subject': 'Toyota Innova Crysta',
        'summary': lang == 'te' ? 'విక్రేత 2016 ఇన్నోవా క్రిస్టాను చూపిస్తున్నారు.' : 'A seller shows a 2016 Innova Crysta.',
        'facts': studyStatus == 'ready' ? _facts : const [],
        'missing': ['kilometres', 'ownership'],
        'suggested_questions': lang == 'te' ? ['ధర ఎంత?', 'ఎన్ని కిలోమీటర్లు?'] : ['What is the asking price?', 'How many kilometres?'],
        if (studyStatus != 'ready') 'message': 'Video content analysis unavailable.',
      };

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    calls.add(('GET', path, null));
    if (path.contains('/study')) {
      return ApiSuccess(<String, Object?>{
        'ref': 'yt_car', 'eligible': true, 'status': studied ? 'ready' : 'none',
        'study': studied ? _study('en') : null,
      } as T);
    }
    return ApiSuccess(<String, Object?>{} as T);
  }

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    calls.add(('POST', path, body));
    final lang = '${(body as Map?)?['language'] ?? 'en'}';
    if (path.endsWith('/study')) {
      studied = true;
      return ApiSuccess(_study(lang) as T);
    }
    if (path.endsWith('/ask')) {
      final q = '${body!['question']}';
      if (notFound.contains(q)) {
        return ApiSuccess(<String, Object?>{
          'found': false,
          'answer': lang == 'te' ? 'ఈ వీడియోలో ఆ వివరాన్ని నిర్ధారించడానికి సమాచారం లేదు.' : 'This video does not have the information to confirm that.',
          'facts': const [], 'timestamps': const [],
        } as T);
      }
      return ApiSuccess(<String, Object?>{
        'found': true,
        'answer': lang == 'te' ? 'విక్రేత ₹12.5 లక్షలు అడుగుతున్నారు.' : 'The seller asks ₹12.5 lakh.',
        'facts': [_facts[3]], 'timestamps': ['1:42'],
      } as T);
    }
    if (path.endsWith('/market')) {
      return ApiSuccess(<String, Object?>{
        'video_facts': {'asking_price': {'text': '₹12.5 lakh', 'value': 1250000, 'basis': 'seller_claim'}},
        'market': {
          'source': 'external', 'label': 'External market information -- not from the video',
          'rows': [
            {'title': '2016 Innova Crysta ZX listing', 'price': 1150000, 'match_source': 'online'},
          ],
          'prices': {'count': 3, 'min': 1150000, 'median': 1210000, 'max': 1300000, 'verified': false},
          'negotiation': {'low': 1150000, 'high': 1250000, 'estimate': true, 'note': 'Estimate'},
          'factors': ['kilometres driven'],
        },
      } as T);
    }
    return ApiSuccess(<String, Object?>{'recorded': true} as T);
  }

  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      post<T>(path, body: body);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      post<T>(path, body: body);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => get<T>(path);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(Uri.parse('mock://$fileName'));

  int count(String method, String suffix) =>
      calls.where((c) => c.$1 == method && c.$2.contains(suffix)).length;
}

UniversalMatch _video({String duration = '0:30', String? format, String id = 'car', String description = ''}) =>
    UniversalMatch.fromJson({
      'id': 'video-yt-$id', 'video_id': 'yt_$id', 'title': 'Innova Crysta for sale $id', 'source': 'video',
      'match_source': 'video', 'destination_url': 'https://www.youtube.com/watch?v=${id.padRight(11, 'x')}',
      'embed_url': 'https://www.youtube-nocookie.com/embed/${id.padRight(11, 'x')}?playsinline=1&rel=0',
      'platform': 'youtube', 'source_name': 'Car Seller', 'duration': duration,
      'subtitle': description, if (format != null) 'video_format': format,
      'image_url': 'https://i.ytimg.com/vi/$id/hqdefault.jpg',
    });

Future<(_StudyApi, List<Uri>, List<String?>)> _pump(WidgetTester tester, UniversalMatch video,
    {_StudyApi? api, String lang = 'en', List<UniversalMatch> related = const []}) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  api ??= _StudyApi();
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
          body: TextButton(
            key: const Key('open'),
            onPressed: () async {
              popped.add(await Navigator.of(context).push<String>(MaterialPageRoute(
                builder: (_) => AskodoxVideoViewerScreen(
                    video: video, telugu: lang == 'te', lang: lang, related: related),
              )));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return (api, embedded, popped);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, duration) in [('30 sec Short', '0:30'), ('1 min', '1:00'), ('2 min', '2:00'), ('exactly 3:00', '3:00')]) {
    testWidgets('$name video: eligible -> study -> fact sheet with basis + timestamps', (tester) async {
      final (api, _, _) = await _pump(tester, _video(duration: duration));
      expect(find.byKey(const Key('askodoxVideoStudyTooLong')), findsNothing);
      await _tap(tester, find.byKey(const Key('askodoxVideoStudyButton')));
      expect(api.count('POST', '/study'), 1);
      expect(find.byKey(const Key('askodoxVideoFactSheet')), findsOneWidget);
      expect(find.text('₹12.5 lakh'), findsOneWidget);
      expect(find.text('Confirmed from video'), findsOneWidget, reason: 'the badge is visible');
      expect(find.text('Seller claim'), findsNWidgets(3));
      expect(find.byKey(const Key('askodoxVideoMissing')), findsOneWidget);
    });
  }

  testWidgets('longer than 3:00: plays normally, never studied, clear message', (tester) async {
    final (api, embedded, _) = await _pump(tester, _video(duration: '3:01'));
    expect(embedded, isNotEmpty, reason: 'still plays in ASKODOX');
    expect(find.text('ASKODOX Video Study is currently available for videos up to 3 minutes.'), findsOneWidget);
    expect(find.byKey(const Key('askodoxVideoStudyButton')), findsNothing);
    expect(api.calls.where((c) => c.$2.contains('/study')), isEmpty, reason: 'no study calls at all');
  });

  testWidgets('grounded Q&A: suggested question, timestamp jump, missing info, cached second question',
      (tester) async {
    final api = _StudyApi(notFound: {'How many kilometres?'});
    final (_, embedded, _) = await _pump(tester, _video(), api: api);
    await _tap(tester, find.byKey(const Key('askodoxVideoStudyButton')));
    await _tap(tester, find.byKey(const ValueKey('askodoxVideoQ-0')));
    expect(find.text('The seller asks ₹12.5 lakh.'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('askodoxVideoAnswerTs-0-1:42')));
    expect(embedded.last.queryParameters['start'], '102', reason: 'jumps to 1:42');
    await _tap(tester, find.byKey(const ValueKey('askodoxVideoQ-1')));
    expect(find.text('This video does not have the information to confirm that.'), findsOneWidget,
        reason: 'never guessed');
    await tester.enterText(find.byKey(const Key('askodoxVideoAskField')), 'What year?');
    await _tap(tester, find.byKey(const Key('askodoxVideoAskSend')));
    expect(api.count('POST', '/ask'), 3);
    expect(api.count('POST', '/study'), 1, reason: 'questions reuse the one study');
  });

  testWidgets('Telugu: study and answers in the conversation language', (tester) async {
    final (_, _, _) = await _pump(tester, _video(), lang: 'te');
    await _tap(tester, find.byKey(const Key('askodoxVideoStudyButton')));
    expect(find.text('వీడియోలో ఉన్నది'), findsOneWidget);
    expect(find.text('విక్రేత చెప్పినది'), findsNWidgets(3));
    await _tap(tester, find.byKey(const ValueKey('askodoxVideoQ-0')));
    expect(find.text('విక్రేత ₹12.5 లక్షలు అడుగుతున్నారు.'), findsOneWidget);
  });

  testWidgets('market comparison is a separate, external section', (tester) async {
    await _pump(tester, _video());
    await _tap(tester, find.byKey(const Key('askodoxVideoStudyButton')));
    await _tap(tester, find.byKey(const Key('askodoxVideoMarket')));
    expect(find.byKey(const Key('askodoxVideoMarketSection')), findsOneWidget);
    expect(find.text('EXTERNAL MARKET INFORMATION -- NOT FROM THE VIDEO'), findsOneWidget);
    expect(find.textContaining('In the video (seller claim): ₹12.5 lakh'), findsOneWidget);
    expect(find.textContaining('(page prices, not verified)'), findsOneWidget);
    expect(find.byKey(const Key('askodoxVideoMarketNegotiation')), findsOneWidget);
  });

  testWidgets('"I\'m interested" continues into the request flow WITH the video\'s details', (tester) async {
    final (_, _, popped) = await _pump(tester, _video());
    await _tap(tester, find.byKey(const Key('askodoxVideoStudyButton')));
    expect(find.textContaining('Contact details are shared only after the seller accepts'), findsOneWidget);
    await _tap(tester, find.byKey(const ValueKey('askodoxVideoAction-interested')));
    expect(popped.single, startsWith(askodoxVideoFollowUpPrefix));
    expect(popped.single, contains('2016 Toyota Innova Crysta'));
    expect(popped.single, contains('asking ₹12.5 lakh'), reason: 'no need to re-type the details');
  });

  testWidgets('content not accessible: honest "Video content analysis unavailable."', (tester) async {
    await _pump(tester, _video(), api: _StudyApi(studyStatus: 'unavailable'));
    await _tap(tester, find.byKey(const Key('askodoxVideoStudyButton')));
    expect(find.text('Video content analysis unavailable.'), findsOneWidget);
    expect(find.byKey(const Key('askodoxVideoFactSheet')), findsNothing);
    expect(find.byKey(const Key('askodoxVideoAskField')), findsNothing, reason: 'no Q&A without evidence');
  });

  testWidgets('description collapsed with More / Show less; related videos visible and play in-app',
      (tester) async {
    final long = List.generate(30, (i) => 'Line $i of a very long YouTube description.').join('\n');
    final related = _video(id: 'next', duration: '2:10');
    final (_, embedded, _) = await _pump(tester, _video(description: long), related: [related]);
    final description = tester.widget<Text>(find.byKey(const Key('askodoxVideoDescription')));
    expect(description.maxLines, 3);
    expect(find.byKey(const ValueKey('askodoxRelatedVideo-video-yt-next')), findsOneWidget,
        reason: 'related videos are visible without expanding the description');
    await _tap(tester, find.byKey(const Key('askodoxVideoDescMore')));
    expect(tester.widget<Text>(find.byKey(const Key('askodoxVideoDescription'))).maxLines, isNull);
    await _tap(tester, find.byKey(const Key('askodoxVideoDescLess')));
    await _tap(tester, find.byKey(const ValueKey('askodoxRelatedVideo-video-yt-next')));
    expect(embedded.last.toString(), contains('nextxxxxxxx'), reason: 'the related video plays in ASKODOX');
  });

  test('Shorts get their own group; normal videos stay in Videos', () {
    final groups = askodoxCompareGroups([
      _video(id: 'short1', duration: '0:40', format: 'short'),
      _video(id: 'normal', duration: '5:00', format: 'video'),
    ]);
    expect(groups.map((g) => g.$1), [AskodoxCompareKind.videos, AskodoxCompareKind.shorts]);
    expect(askodoxCompareLabel(AskodoxCompareKind.shorts, 'te'), 'షార్ట్స్');
    expect(askodoxDurationSeconds('3:00'), 180);
    expect(askodoxDurationSeconds('1:02:03'), 3723);
  });

  testWidgets('uploaded short video: its study opens from the attachment reference', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final api = _StudyApi()..studied = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(api)],
      child: const MaterialApp(home: Scaffold(body: SingleChildScrollView(
          child: AskodoxVideoStudyPanel(videoRef: 'up_abc', durationSeconds: 95)))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxVideoFactSheet')), findsOneWidget, reason: 'cached study, no re-analysis');
    expect(api.count('POST', '/study'), 0);
  });

  test('attachment response carries the upload study reference', () async {
    final service = ApiChatAttachmentService(_AttachApi({
      'status': 'success', 'facts': 'Video shows: a white car', 'attachment': {'id': 'att_1', 'kind': 'video'},
      'analysis': {}, 'video_study': {'ref': 'up_abc', 'status': 'ready', 'eligible': true},
    }));
    final result = await service.analyze(
        ChatAttachment(name: 'car.mp4', bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'video/mp4'),
        userText: '', language: 'en');
    expect(result.videoStudy?['ref'], 'up_abc');
    final long = await ApiChatAttachmentService(_AttachApi({
      'status': 'success', 'facts': 'Video attached (4:10), not studied. ASKODOX Video Study is currently available '
          'for videos up to 3 minutes.', 'attachment': {'id': 'att_2', 'kind': 'video'}, 'analysis': {},
      'video_study': {'ref': null, 'status': 'not_eligible', 'reason': 'too_long', 'eligible': false},
    })).analyze(ChatAttachment(name: 'long.mp4', bytes: Uint8List.fromList([1]), mimeType: 'video/mp4'),
        userText: '', language: 'en');
    expect(long.facts, contains('up to 3 minutes'), reason: 'kept as an attachment, honestly not studied');
    expect(long.videoStudy?['reason'], 'too_long');
  });
}

class _AttachApi extends _StudyApi {
  _AttachApi(this.reply);
  final Map<String, Object?> reply;

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(reply as T);
}
