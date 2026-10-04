import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/auth/auth_controller.dart';
import 'package:podx/core/auth/auth_models.dart';
import 'package:podx/core/providers/backend_providers.dart';
import 'package:podx/features/native_video/native_video.dart';
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

void main() {
  reelTests();
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
