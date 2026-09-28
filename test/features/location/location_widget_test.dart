import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/features/location/application/location_controller.dart';
import 'package:podx/features/location/data/mock_geo_repository.dart';
import 'package:podx/features/location/domain/geo_models.dart';
import 'package:podx/features/location/presentation/location_setup_screen.dart';
import 'package:podx/features/location/presentation/nearby_shops_screen.dart';

import 'fakes/fake_device_location_gateway.dart';
void main(){testWidgets('location is one step: use my location or search a place (map optional)',(tester)async{await tester.pumpWidget(const ProviderScope(child:MaterialApp(home:LocationSetupScreen())));await tester.pump();expect(find.byKey(const Key('askodoxUseMyLocation')),findsOneWidget);expect(find.byKey(const Key('askodoxLocationSearch')),findsOneWidget);expect(find.byKey(const Key('askodoxPickOnMap')),findsOneWidget);expect(find.textContaining('testing'),findsNothing);expect(find.textContaining('future release'),findsNothing);expect(find.text('Banjara Hills'),findsNothing);});testWidgets('map and list view toggle',(tester)async{final c=LocationController(MockGeoRepository(),FakeDeviceLocationGateway());await c.refresh();await tester.pumpWidget(ProviderScope(overrides:[locationControllerProvider.overrideWith((ref)=>c)],child:const MaterialApp(home:NearbyShopsScreen())));await tester.pumpAndSettle();expect(find.byKey(const Key('mockMap')),findsOneWidget);await tester.tap(find.text('List'));await tester.pump();expect(c.state.mode,MapDisplayMode.list);expect(find.byKey(const Key('mockMap')),findsNothing);});}
