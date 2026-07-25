import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/location/application/location_controller.dart';
import 'package:podx/features/location/data/mock_geo_repository.dart';
import 'package:podx/features/location/domain/geo_models.dart';
import 'package:podx/features/location/presentation/location_setup_screen.dart';
import 'package:podx/features/location/presentation/nearby_shops_screen.dart';
void main(){testWidgets('manual location selection is available',(tester)async{await tester.pumpWidget(const ProviderScope(child:MaterialApp(home:LocationSetupScreen())));expect(find.text('Choose manually'),findsOneWidget);expect(find.text('Banjara Hills'),findsOneWidget);});testWidgets('map and list view toggle',(tester)async{final c=LocationController(MockGeoRepository());await c.refresh();await tester.pumpWidget(ProviderScope(overrides:[locationControllerProvider.overrideWith((ref)=>c)],child:const MaterialApp(home:NearbyShopsScreen())));await tester.pumpAndSettle();expect(find.byKey(const Key('mockMap')),findsOneWidget);await tester.tap(find.text('List'));await tester.pump();expect(c.state.mode,MapDisplayMode.list);expect(find.byKey(const Key('mockMap')),findsNothing);});}
