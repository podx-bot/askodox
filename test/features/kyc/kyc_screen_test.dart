import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/kyc/data/kyc_repository.dart';
import 'package:podx/features/kyc/presentation/kyc_screen.dart';
import 'package:podx/services/chat_attachment_service.dart';
import 'package:podx/services/media_picker.dart';

class _Api implements ApiClient {
  bool consent = false;
  final posts = <String, Object?>{};
  bool withdrawn = false;

  Map<String, Object?> get _me => {
        'level': 1,
        'level_label': 'Mobile verified',
        'consent': consent,
        'consent_text': 'I allow ASKODOX to read the documents I choose.',
        'consent_version': 'kyc-consent-v1',
        'badges': [
          {'level': 1, 'label': 'Mobile verified'},
        ],
        'checks': consent
            ? [
                {
                  'id': 'kyc_1',
                  'kind': 'pan',
                  'label': 'PAN card',
                  'status': 'AWAITING_PROVIDER',
                  'method': 'ai_extraction',
                  'fields': {'pan': '••••••234F'},
                  'issues': [],
                  'next_steps': ['PAN card verification needs an authorised provider, which is not enabled yet.'],
                },
              ]
            : [],
        'requirements': {
          'buy': {'min_level': 1, 'met': true},
          'receive_payouts': {'min_level': 2, 'met': false},
        },
      };

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(_me as T);

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts[path] = body;
    if (path == '/api/kyc/consent') consent = true;
    if (path == '/api/kyc/documents') {
      return ApiSuccess(<String, Object?>{
        'check': {'status': 'AWAITING_PROVIDER'},
        'issues': [],
        'next_steps': ['Your masked details are saved; nothing more is needed now.'],
      } as T);
    }
    return ApiSuccess(<String, Object?>{} as T);
  }

  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async {
    withdrawn = true;
    consent = false;
    return ApiSuccess(<String, Object?>{'withdrawn': true} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _Picker implements AskodoxMediaPicker {
  @override
  Future<List<ChatAttachment>> pick(String source) async =>
      [ChatAttachment(name: 'pan.jpg', bytes: Uint8List.fromList([1, 2, 3]))];
}

void main() {
  testWidgets('consent first, document read (masked, not verified), withdraw deletes', (tester) async {
    final api = _Api();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        kycRepositoryProvider.overrideWithValue(KycRepository(api, authToken: 't')),
        askodoxMediaPickerProvider.overrideWithValue(_Picker()),
      ],
      child: const MaterialApp(home: AskodoxKycScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Level 1 · Mobile verified'), findsOneWidget);
    expect(find.byKey(const Key('askodoxKycAddDocument')), findsNothing, reason: 'no documents before consent');
    await tester.tap(find.byKey(const Key('askodoxKycAccept')));
    await tester.pumpAndSettle();
    expect(api.posts['/api/kyc/consent'], {'accept': true, 'version': 'kyc-consent-v1'});
    expect(find.textContaining('Waiting for a verification provider'), findsOneWidget,
        reason: 'AI-read details are never shown as verified');
    expect(find.textContaining('••••••234F'), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxKycAddDocument')));
    await tester.pumpAndSettle();
    final sent = api.posts['/api/kyc/documents'] as Map;
    expect(sent['filename'], 'pan.jpg');
    expect(sent['file_base64'], 'AQID');
    expect(find.textContaining('nothing more is needed now'), findsWidgets);
    await tester.tap(find.byKey(const Key('askodoxKycWithdraw')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('askodoxKycWithdrawConfirm')));
    await tester.pumpAndSettle();
    expect(api.withdrawn, isTrue);
    expect(find.byKey(const Key('askodoxKycAccept')), findsOneWidget);
  });
}
