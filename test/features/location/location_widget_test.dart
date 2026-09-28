import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/location/presentation/location_setup_screen.dart';

void main(){testWidgets('location is one step: use my location or search a place (map optional)',(tester)async{await tester.pumpWidget(const ProviderScope(child:MaterialApp(home:LocationSetupScreen())));await tester.pump();expect(find.byKey(const Key('askodoxUseMyLocation')),findsOneWidget);expect(find.byKey(const Key('askodoxLocationSearch')),findsOneWidget);expect(find.byKey(const Key('askodoxPickOnMap')),findsOneWidget);expect(find.textContaining('testing'),findsNothing);expect(find.textContaining('future release'),findsNothing);expect(find.text('Banjara Hills'),findsNothing);});}
