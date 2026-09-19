import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/home/presentation/askodox_primary_home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.askodox.app/device');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('primary home orb starts voice inside Main Chat', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'startVoiceSearch') return '';
      return null;
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: AskodoxPrimaryHomeScreen()),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const Key('askodoxHomeOrb')));
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'startVoiceSearch');
    expect(calls.single.arguments, {'languageCode': 'en'});
    expect(tester.takeException(), isNull);
  });
}