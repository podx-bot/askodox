import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/features/home/application/conversation_archive.dart';
import 'package:podx/features/native_video/native_video.dart';
import 'package:podx/features/native_video/video_commerce.dart';
import 'package:podx/services/chat_attachment_service.dart';
import 'package:podx/services/media_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedIn extends AuthController {
  _SignedIn(super.manager) {
    state = AuthSession(
      user: const AuthUser(id: 'app-phone-919800000000', role: UserRole.seller, displayName: 'Ravi'),
      status: AuthStatus.loggedIn,
      tokenPlaceholder: 't',
      expiresAt: DateTime.now().add(const Duration(days: 1)),
    );
  }
}

class _Picker implements AskodoxMediaPicker {
  @override
  Future<List<ChatAttachment>> pick(String source) async =>
      [ChatAttachment(name: 'demo.mp4', bytes: Uint8List.fromList(List.filled(2048, 1)), mimeType: 'video/mp4')];
}

class _Repo implements NativeVideoRepository {
  final uploads = <String>[];
  final videos = <NativeVideo>[];

  @override
  Future<String?> upload({required List<int> bytes, required String fileName, required String title,
      String caption = '', String category = '', String products = '', bool asBusiness = false,
      bool submit = true}) async {
    uploads.add('$title|$category|$submit|${bytes.length}');
    videos.add(NativeVideo(id: 'vid_1', status: submit ? 'PENDING_REVIEW' : 'DRAFT', title: title));
    return null;
  }

  @override
  Future<List<NativeVideo>> mine() async => List.of(videos);
  @override
  Future<List<NativeVideo>> feed({String category = ''}) async => const [];
  @override
  Future<bool> act(String id, String action) async => true;
  @override
  Future<bool> report(String id, String reason) async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _Commerce extends VideoCommerceRepository {
  _Commerce() : super(MockApiClient(), 't');
  final events = <String>[];
  final edits = <Map<String, Object?>>[];
  final posted = <String>[];
  final decided = <String>[];
  final approved = <String>[];
  final settings = <String>[];
  String status = 'DRAFT';

  @override
  Future<void> event(String id, String kind, {String area = ''}) async => events.add('$id:$kind');

  @override
  Future<Map<String, Object?>> detail(String id) async => {
        'id': id, 'status': status, 'tags': const ['jump', 'starter'],
        'visible_in': status == 'ACTIVE' ? const ['ASKODOX videos feed', 'Search results when relevant (video section)'] : const [],
        'listings': const [], 'preorder': {'enabled': true, 'available_date': '2026-11-01', 'expected_price': 4999,
            'price_confirmed': false}};

  @override
  Future<Map<String, Object?>> analytics(String id) async => {'views': 12, 'questions': 3, 'unanswered': 1,
        'ai_answered': 2, 'shares': 1, 'pre_orders': 1, 'top_questions': [{'topic': 'bike inflate tyres', 'count': 2}],
        'demand_by_area': [{'area': 'Benz Circle', 'count': 4}]};

  @override
  Future<List<Map<String, Object?>>> comments(String id) async => [
        {'id': 'vc_1', 'kind': 'question', 'text': 'Does it inflate bike tyres?', 'reply': 'Yes [0:12]',
          'reply_by': 'askodox_ai', 'reply_status': 'ai_answered', 'basis': 'seen_in_video', 'status': 'VISIBLE'},
      ];

  @override
  Future<Map<String, Object?>> suggest(String id) async => {'status': 'ready', 'suggestions': {
        'title': 'JPT 4-in-1 jump starter', 'caption': 'Jump starts a car and inflates tyres.',
        'category': 'product', 'subcategory': 'car_accessories', 'category_path': ['Products', 'Car accessories'],
        'brand': 'JPT', 'features': ['Air compressor: 150 PSI'], 'tags': ['jump', 'starter'],
        'not_established': ['warranty']}};

  @override
  Future<({Map<String, Object?> data, String? error})> edit(String id, Map<String, Object?> fields) async {
    edits.add(fields);
    return (data: <String, Object?>{'returned_to_review': false}, error: null);
  }

  @override
  Future<({Map<String, Object?> data, String? error})> comment(String id, String text,
      {String kind = 'question', String language = 'en'}) async {
    posted.add(text);
    return (data: <String, Object?>{'reply_status': 'waiting_seller', 'notice': 'Asked the seller -- you will see their reply here.'},
        error: null);
  }

  @override
  Future<({Map<String, Object?> data, String? error})> preorder(String id,
          {double quantity = 1, String variant = '', String note = '', String listingId = ''}) async =>
      (data: <String, Object?>{'message': 'Pre-order sent -- not confirmed until the seller accepts.'}, error: null);

  @override
  Future<Map<String, Object?>> share(String id) async => {'text': 'JPT demo -- watch on ASKODOX: https://x/v/$id'};

  @override
  Future<Map<String, Object?>> inbox() async => {
        'settings': {'mode': settings.isEmpty ? 'draft' : settings.last.split(':').first, 'paused': false},
        'needs_me': [{'id': 'vc_2', 'kind': 'question', 'text': 'Can you give a discount?', 'reply_status': 'waiting_seller', 'status': 'VISIBLE'}],
        'drafts': [{'id': 'vc_3', 'kind': 'question', 'text': 'Battery size?', 'reply': '12000 mAh',
          'reply_by': 'askodox_ai_draft', 'reply_status': 'draft_pending', 'basis': 'seen_in_video', 'status': 'VISIBLE'}],
        'answered': const [],
        'pre_orders': [{'id': 'vp_1', 'quantity': 2, 'status': decided.isEmpty ? 'REQUESTED' : 'ACCEPTED',
          if (decided.isNotEmpty) 'buyer_phone': '+919800000001'}],
      };

  @override
  Future<Map<String, Object?>> saveAiSettings(String mode, bool paused) async {
    settings.add('$mode:$paused');
    return {'mode': mode, 'paused': paused};
  }

  @override
  Future<bool> approve(String commentId) async {
    approved.add(commentId);
    return true;
  }

  @override
  Future<Map<String, Object?>> decide(String preorderId, bool accept) async {
    decided.add('$preorderId:$accept');
    return {'status': accept ? 'ACCEPTED' : 'DECLINED'};
  }
}

void main() {
  reelTests();
  commerceTests();
  test('owner actions follow the review lifecycle', () {
    expect(askodoxVideoOwnerActions('DRAFT'), ['submit', 'remove']);
    expect(askodoxVideoOwnerActions('PENDING_REVIEW'), ['remove']);
    expect(askodoxVideoOwnerActions('ACTIVE'), ['pause', 'remove']);
    expect(askodoxVideoOwnerActions('PAUSED'), ['resume', 'remove']);
    expect(NativeVideo.fromJson({'id': 'v', 'status': 'ACTIVE', 'data': {'title': 'T', 'description': 'c'}}).caption, 'c');
  });

  testWidgets('pick, title and upload goes to review; the feed says honestly when empty', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _Repo();
    await tester.pumpWidget(ProviderScope(overrides: [
      authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
      nativeVideoRepositoryProvider.overrideWithValue(repo),
      videoCommerceRepositoryProvider.overrideWithValue(_Commerce()),
      askodoxMediaPickerProvider.overrideWithValue(_Picker()),
    ], child: const MaterialApp(home: NativeVideoScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('video-upload')));
    await tester.pumpAndSettle();
    expect(repo.uploads, isEmpty, reason: 'no video chosen yet');
    await tester.tap(find.byKey(const ValueKey('video-pick-gallery')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-picked')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('video-title')), 'Rice cooker demo');
    await tester.ensureVisible(find.byKey(const ValueKey('video-upload')));
    await tester.tap(find.byKey(const ValueKey('video-upload')));
    await tester.pumpAndSettle();
    expect(repo.uploads, ['Rice cooker demo||true|2048']);
    await tester.scrollUntilVisible(find.text('Waiting for review'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Waiting for review'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('No ASKODOX videos are published yet.'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('No ASKODOX videos are published yet.'), findsOneWidget);
  });
}

class _ReelRepo extends _Repo {
  final asked = <String>[];

  @override
  Future<VideoMessageResult> message(String id, String text) async {
    asked.add('$id:$text');
    return const VideoMessageResult(status: 'WAITING_FOR_OWNER');
  }

  @override
  Future<Map<String, Object?>> study(String id, {String language = 'en'}) async =>
      {'status': 'ready', 'ref': 'nv_$id', 'suggested_questions': ['What is the capacity?']};

  @override
  Future<Map<String, Object?>> ask(String studyRef, String question, {String language = 'en'}) async =>
      {'found': false, 'answer': 'Not in this video.'};

  @override
  Future<({List<Map<String, Object?>> inbox, List<Map<String, Object?>> sent})> messages() async =>
      (inbox: const <Map<String, Object?>>[], sent: const <Map<String, Object?>>[]);

  @override
  Future<bool> reply(String messageId, String text) async => true;
}

void reelTests() {
  testWidgets('reels: ask the business hands off honestly; questions answer only from the video', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final repo = _ReelRepo();
    const videos = [NativeVideo(id: 'vid_1', status: 'ACTIVE', title: 'Rice cooker demo', url: 'https://x/v.mp4',
        label: 'From the business')];
    await tester.pumpWidget(ProviderScope(overrides: [
      authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
      nativeVideoRepositoryProvider.overrideWithValue(repo),
      videoCommerceRepositoryProvider.overrideWithValue(_Commerce()),
      askodoxVideoSurfaceProvider.overrideWithValue((context, video, active) => Text('playing ${video.id} $active')),
    ], child: const MaterialApp(home: NativeReelsScreen(videos: videos))));
    await tester.pumpAndSettle();
    expect(find.text('playing vid_1 true'), findsOneWidget);
    expect(find.text('From the business'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reel-ask-vid_1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reel-prompt')), 'Do you deliver?');
    await tester.tap(find.byKey(const ValueKey('reel-prompt-send')));
    await tester.pumpAndSettle();
    expect(repo.asked, ['vid_1:Do you deliver?']);
    expect(find.textContaining('The business will reply'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reel-study-vid_1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('reel-prompt')), 'Is there a warranty?');
    await tester.tap(find.byKey(const ValueKey('reel-prompt-send')));
    await tester.pumpAndSettle();
    expect(find.text('Not in this video.'), findsOneWidget);
  });
}


void commerceTests() {
  Widget app(Widget home, _Commerce commerce, {List<String>? shared}) => ProviderScope(overrides: [
        authSessionProvider.overrideWith((ref) => _SignedIn(ref.watch(sessionManagerProvider))),
        nativeVideoRepositoryProvider.overrideWithValue(_ReelRepo()),
        videoCommerceRepositoryProvider.overrideWithValue(commerce),
        askodoxShareTextProvider.overrideWithValue((text, {subject = ''}) async {
          shared?.add(text);
          return true;
        }),
        askodoxVideoSurfaceProvider.overrideWithValue((context, video, active) => Text('playing ${video.id}')),
      ], child: MaterialApp(home: home));

  testWidgets('owner: status, not visible until published, suggestions only from the video, save', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final commerce = _Commerce();
    await tester.pumpWidget(app(const MyVideoDetailScreen(
        video: NativeVideo(id: 'vid_9', status: 'DRAFT', title: 'my clip', url: 'https://x/v.mp4')), commerce));
    await tester.pumpAndSettle();
    expect(find.text('Draft'), findsOneWidget);
    expect(find.byKey(const ValueKey('video-not-visible')), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video-suggest')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('video-suggestions')), findsOneWidget);
    expect(find.textContaining('Air compressor: 150 PSI (seen in video)'), findsOneWidget);
    expect(find.textContaining('Not established in the video: warranty'), findsOneWidget);
    expect(find.textContaining('Products › Car accessories'), findsOneWidget);
    expect(commerce.edits, isEmpty, reason: 'suggestions are never saved automatically');
    final save = find.byKey(const ValueKey('video-save'));
    await tester.scrollUntilVisible(save, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(commerce.edits.single['title'], 'JPT 4-in-1 jump starter');
    expect(commerce.edits.single['category'], 'car_accessories');
    expect(commerce.edits.single['preorder_enabled'], isTrue);
  });

  testWidgets('owner: published video shows where it appears, analytics, labelled AI answers; share sheet only',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final commerce = _Commerce()..status = 'ACTIVE';
    final shared = <String>[];
    await tester.pumpWidget(app(const MyVideoDetailScreen(
        video: NativeVideo(id: 'vid_9', status: 'ACTIVE', title: 'JPT demo', url: 'https://x/v.mp4')), commerce,
        shared: shared));
    await tester.pumpAndSettle();
    expect(find.text('Approved · Published'), findsOneWidget);
    expect(find.text('View published'), findsOneWidget);
    expect(find.text('• ASKODOX videos feed'), findsOneWidget);
    final share = find.byKey(const ValueKey('video-share'));
    await tester.scrollUntilVisible(share, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(share);
    await tester.pumpAndSettle();
    expect(shared.single, contains('watch on ASKODOX'));
    expect(commerce.events, contains('vid_9:share'));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('video-comment-vc_1')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Interest by area: Benz Circle (4)'), findsOneWidget);
    expect(find.textContaining('ASKODOX AI answer: Yes [0:12]'), findsOneWidget);
    expect(find.text('Seen in video'), findsOneWidget);
  });

  testWidgets('seller inbox: AI mode, pause, approve draft, accept pre-order reveals buyer only then', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final commerce = _Commerce();
    await tester.pumpWidget(app(const VideoSellerInboxScreen(), commerce));
    await tester.pumpAndSettle();
    expect(find.textContaining('Never automatic'), findsOneWidget);
    await tester.tap(find.text('Auto'));
    await tester.pumpAndSettle();
    expect(commerce.settings.last, 'auto:false');
    await tester.tap(find.byKey(const ValueKey('video-ai-pause')));
    await tester.pumpAndSettle();
    expect(commerce.settings.last, 'auto:true', reason: 'pause = seller takes over');
    expect(find.text('Can you give a discount?'), findsOneWidget);
    expect(find.textContaining('AI draft (needs your approval): 12000 mAh'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video-approve-vc_3')));
    await tester.pumpAndSettle();
    expect(commerce.approved, ['vc_3']);
    expect(find.textContaining('+9198'), findsNothing, reason: 'no buyer phone before acceptance');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('video-preorder-accept-vp_1')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('video-preorder-accept-vp_1')));
    await tester.pumpAndSettle();
    expect(commerce.decided, ['vp_1:true']);
    expect(find.textContaining('+919800000001'), findsOneWidget);
  });

  testWidgets('customer reels: view counted, questions sheet + pre-order, ask in chat carries the video', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final commerce = _Commerce()..status = 'ACTIVE';
    late ProviderContainer container;
    const video = NativeVideo(id: 'vid_5', status: 'ACTIVE', title: 'JPT demo', url: 'https://x/v.mp4');
    await tester.pumpWidget(app(Consumer(builder: (context, ref, _) {
      container = ProviderScope.containerOf(context);
      return const NativeReelsScreen(videos: [video]);
    }), commerce));
    await tester.pumpAndSettle();
    expect(commerce.events, ['vid_5:view']);
    await tester.tap(find.byKey(const ValueKey('reel-questions-vid_5')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pre-order · 2026-11-01 · ₹4999 (expected)'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('video-question-field')), 'What is the warranty?');
    await tester.tap(find.byKey(const ValueKey('video-question-send')));
    await tester.pumpAndSettle();
    expect(commerce.posted, ['What is the warranty?']);
    expect(find.textContaining('Asked the seller'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('video-preorder')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('prompt-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining('not confirmed until the seller accepts'), findsOneWidget);
    expect(container.read(askodoxChatRequestProvider), isNull);
  });

  test('lifecycle labels', () {
    expect(askodoxVideoLifecycleLabel('PENDING_REVIEW', false), 'Waiting for review');
    expect(askodoxVideoLifecycleLabel('DRAFT', false, processing: true), 'Processing');
    expect(askodoxVideoLifecycleLabel('REJECTED', false), 'Rejected');
    expect(askodoxVideoLifecycleLabel('PAUSED', false), 'Paused');
    expect(AskodoxChatRequest.aboutVideo('nv_5', 'JPT demo').videoRef, 'nv_5');
  });
}
