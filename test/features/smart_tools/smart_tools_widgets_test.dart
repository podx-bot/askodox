import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/smart_tools/data/vision_inspection_repository.dart';
import 'package:podx/features/smart_tools/domain/sensor_math.dart';
import 'package:podx/features/smart_tools/presentation/calculator_screens.dart';
import 'package:podx/features/smart_tools/presentation/inspection_screen.dart';
import 'package:podx/features/smart_tools/presentation/sensor_tools_screen.dart';
import 'package:podx/features/smart_tools/presentation/smart_tools_hub_screen.dart';
import 'package:podx/services/chat_attachment_service.dart';
import 'package:podx/services/media_picker.dart';

class _FakeSensors implements AskodoxMotionSensors {
  _FakeSensors({this.silent = false});
  final bool silent;
  final accel = StreamController<AskodoxVec3>.broadcast();
  final mag = StreamController<AskodoxVec3>.broadcast();
  @override
  Stream<AskodoxVec3> accelerometer() => accel.stream;
  @override
  Stream<AskodoxVec3> magnetometer() => mag.stream;
}

class _ScriptedClient implements ApiClient {
  final posts = <String, Object?>{};
  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) async =>
      ApiSuccess(<String, Object?>{
        'profiles': [
          {'domain': 'general', 'label': 'General inspection', 'guidance': <String>[]},
          {'domain': 'food', 'label': 'Food quality & freshness', 'guidance': ['Photograph in daylight.']},
        ],
      } as T);

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) async {
    posts[path] = body;
    return ApiSuccess(<String, Object?>{
      'status': 'success',
      'facts': 'Inspection (food, quick): chicken.',
      'report': {
        'domain': 'food', 'mode': 'quick', 'status': 'ok', 'subject': 'Chicken pieces',
        'observed': [{'finding': 'Pink flesh, moist surface', 'region': 'centre', 'confidence': 0.9}],
        'inferred': [{'finding': 'Likely cut today', 'basis': 'colour', 'confidence': 0.6}],
        'not_verifiable': ['Whether it is safe to eat cannot be confirmed from a photo.'],
        'recommended_checks': ['Smell and feel the item before buying.'],
        'safety_warnings': ['A photo cannot certify that food is safe to eat.'],
        'quantities': <Object?>[], 'needs_more_evidence': <Object?>[], 'limits': ['Photos only.'],
        'confidence': 0.6, 'cost': {'cached': false},
      },
    } as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePicker implements AskodoxMediaPicker {
  @override
  Future<List<ChatAttachment>> pick(String source) async =>
      [ChatAttachment(name: 'chicken.jpg', bytes: Uint8List.fromList([1, 2, 3]), mimeType: 'image/jpeg')];
}

void _tallView(WidgetTester tester) {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester, Widget child, {List<Override> overrides = const []}) async {
  _tallView(tester);
  await tester.pumpWidget(ProviderScope(overrides: overrides, child: MaterialApp(home: child)));
  await tester.pump();
}

void main() {
  testWidgets('brick calculator shows an estimate with assumptions as values are typed', (tester) async {
    await _pump(tester, AskodoxCalculatorScreen(spec: askodoxCalcSpecs['brick']!));
    expect(find.byKey(const Key('askodoxToolResult')), findsNothing, reason: 'nothing guessed before input');
    await tester.enterText(find.byKey(const ValueKey('askodoxCalcField-length')), '3');
    await tester.enterText(find.byKey(const ValueKey('askodoxCalcField-height')), '3');
    await tester.pump();
    expect(find.byKey(const Key('askodoxToolResult')), findsOneWidget);
    expect(find.text('Bricks / blocks'), findsOneWidget);
    expect(find.textContaining('not a structural design'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('askodoxCalcField-wastage')), '80');
    await tester.pump();
    expect(find.byKey(const Key('askodoxToolError')), findsOneWidget);
  });

  testWidgets('area calculator switches fields by shape', (tester) async {
    await _pump(tester, AskodoxCalculatorScreen(spec: askodoxCalcSpecs['area']!));
    expect(find.byKey(const ValueKey('askodoxCalcField-d')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('askodoxCalcChoice-circle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('askodoxCalcField-d')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('askodoxCalcField-d')), '2');
    await tester.pump();
    expect(find.text('3.14 m²'), findsOneWidget);
  });

  testWidgets('hub: built tools open, unbuilt tools explain instead of pretending', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const AskodoxSmartToolsHubScreen()),
      GoRoute(path: '/tools/calc/:id', builder: (_, state) => Text('CALC ${state.pathParameters['id']}')),
    ]);
    _tallView(tester);
    await tester.pumpWidget(ProviderScope(child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    final pairing = find.byKey(const ValueKey('askodoxTool-pairing'));
    await tester.scrollUntilVisible(pairing, 300);
    await tester.ensureVisible(pairing);
    await tester.pumpAndSettle();
    expect(find.descendant(of: pairing, matching: find.text('Coming soon')), findsOneWidget);
    await tester.tap(pairing);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('askodoxToolInfo-pairing')), findsOneWidget);
    expect(find.textContaining('will not pretend'), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const ValueKey('askodoxToolInfo-pairing')))).pop();
    await tester.pumpAndSettle();
    final brick = find.byKey(const ValueKey('askodoxTool-brick'));
    await tester.scrollUntilVisible(brick, -300);
    await tester.ensureVisible(brick);
    await tester.pumpAndSettle();
    await tester.tap(brick);
    await tester.pumpAndSettle();
    expect(find.text('CALC brick'), findsOneWidget);
  });

  testWidgets('level reads the accelerometer and can be zeroed', (tester) async {
    final sensors = _FakeSensors();
    await _pump(tester, const AskodoxLevelScreen(), overrides: [askodoxMotionSensorsProvider.overrideWithValue(sensors)]);
    sensors.accel.add(const AskodoxVec3(0, 0, 9.8));
    await tester.pump();
    expect(find.text('Level ✓'), findsOneWidget);
    sensors.accel.add(const AskodoxVec3(1.7, 0, 9.65));
    for (var i = 0; i < 40; i++) {
      sensors.accel.add(const AskodoxVec3(1.7, 0, 9.65));
      await tester.pump();
    }
    expect(find.text('Level ✓'), findsNothing);
    await tester.tap(find.byKey(const Key('askodoxLevelCalibrate')));
    await tester.pump();
    expect(find.text('Level ✓'), findsOneWidget, reason: 'zeroed on this surface');
    await tester.pump(askodoxSensorTimeout);
  });

  testWidgets('no sensor events -> honest "sensor not available"', (tester) async {
    await _pump(tester, const AskodoxCompassScreen(),
        overrides: [askodoxMotionSensorsProvider.overrideWithValue(_FakeSensors(silent: true))]);
    await tester.pump(askodoxSensorTimeout + const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxSensorUnavailable')), findsOneWidget);
  });

  testWidgets('compass shows heading and the magnetic-north caveat', (tester) async {
    final sensors = _FakeSensors();
    await _pump(tester, const AskodoxCompassScreen(),
        overrides: [askodoxMotionSensorsProvider.overrideWithValue(sensors)]);
    sensors.accel.add(const AskodoxVec3(0, 0, 9.8));
    sensors.mag.add(const AskodoxVec3(-20, 0, -40));
    await tester.pump();
    expect(find.text('90° E'), findsOneWidget);
    expect(find.text('Magnetic north (not true north)'), findsOneWidget);
    await tester.pump(askodoxSensorTimeout);
  });

  testWidgets('inspection: photo -> evidence report with the cannot-confirm section', (tester) async {
    final client = _ScriptedClient();
    await _pump(tester, const AskodoxInspectionScreen(initialDomain: 'food'), overrides: [
      askodoxVisionInspectionRepositoryProvider.overrideWithValue(AskodoxVisionInspectionRepository(client)),
      askodoxMediaPickerProvider.overrideWithValue(_FakePicker()),
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Photograph in daylight.'), findsOneWidget, reason: 'server capture guidance');
    final run = tester.widget<FilledButton>(find.byKey(const Key('askodoxInspectRun')));
    expect(run.onPressed, isNull, reason: 'no photo, no call');
    await tester.tap(find.byKey(const Key('askodoxInspectCamera')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('askodoxInspectRun')));
    await tester.tap(find.byKey(const Key('askodoxInspectRun')));
    await tester.pumpAndSettle();
    final body = client.posts['/api/vision/inspect'] as Map;
    expect(body['domain'], 'food');
    expect(body['mode'], 'quick');
    expect((body['images'] as List).single['mime_type'], 'image/jpeg');
    expect(find.byKey(const Key('askodoxInspectionReport')), findsOneWidget);
    expect(find.text('Cannot be confirmed from a photo'), findsOneWidget);
    expect(find.textContaining('safe to eat cannot be confirmed'), findsOneWidget);
  });
}
