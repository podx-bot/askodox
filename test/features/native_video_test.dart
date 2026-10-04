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
}

void main() {
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
