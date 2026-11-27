import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/pos/data/pos_repository.dart';
import 'package:podx/features/steps/presentation/agent_team_screens.dart';

/// Owner 2026-11-28: the agent team pages -- OK inbox, History, Team settings (made-up data only).
class _Api implements ApiClient {
  _Api(this.reply);
  final Object? Function(String method, String path, Object? body) reply;
  final calls = <String, Object?>{};

  Future<ApiResult<T>> _go<T>(String method, String path, Object? body) async {
    calls['$method $path'] = body;
    return ApiSuccess(reply(method, path, body) as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('GET', path.split('?').first, null);
  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('POST', path, body);
  @override
  Future<ApiResult<T>> put<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PUT', path, body);
  @override
  Future<ApiResult<T>> patch<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _go('PATCH', path, body);
  @override
  Future<ApiResult<T>> delete<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _go('DELETE', path, null);
  @override
  Future<ApiResult<Uri>> upload(String path,
          {required List<int> bytes, required String fileName, ApiRequestOptions options = const ApiRequestOptions()}) =>
      throw UnimplementedError();
}

Future<void> _pump(WidgetTester tester, _Api api, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2340); // 360 x 780 dp
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxPosRepositoryProvider.overrideWithValue(AskodoxPosRepository(api, authToken: 't'))],
    child: MaterialApp(home: child),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}


const _settings = {
  'is_owner': true,
  'agents_off': <Object?>[],
  'approvers': 'owner_manager',
  'all_agents': [
    {'id': 'sales', 'name_en': 'Sales agent', 'name_te': 'సేల్స్ ఏజెంట్'},
    {'id': 'inventory', 'name_en': 'Inventory agent', 'name_te': 'స్టాక్ ఏజెంట్'},
  ],
};

final _pending = {
  'id': 'a1',
  'agent': 'inventory',
  'summary': 'Change stock of Tea',
  'status': 'PENDING_APPROVAL',
  'risk': 'sensitive',
  'proposed_at': '2026-11-28T09:40:00+05:30',
  'mine': false,
};

void main() {
  testWidgets('inbox: a waiting job can be approved and the owner is told who may say yes', (tester) async {
    final api = _Api((m, path, b) {
      if (path.endsWith('/agent-team')) return {'pending': 1, 'recent': <Object?>[], 'agents': <Object?>[], 'settings': _settings};
      if (path.endsWith('/agent-actions')) return {'actions': [_pending]};
      if (path.endsWith('/decision')) return {'id': 'a1', 'status': 'DONE'};
      return {'id': 'b1', 'my_role': 'owner'};
    });
    await _pump(tester, api, const AskodoxAgentInboxScreen(businessId: 'b1'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('askodoxAgentInboxItem-a1')), findsOneWidget);
    expect(find.text('Change stock of Tea'), findsOneWidget);
    expect(find.byKey(const Key('askodoxAgentInboxRule')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxAgentInboxApprove-a1')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.calls.containsKey('POST /api/pos/businesses/b1/agent-actions/a1/decision'), isTrue);
    expect(api.calls['POST /api/pos/businesses/b1/agent-actions/a1/decision'], {'approve': true, 'note': ''});
  });

  testWidgets('inbox: a manager sees no buttons when the owner kept approvals to themself', (tester) async {
    final api = _Api((m, path, b) {
      if (path.endsWith('/agent-team')) {
        return {'pending': 1, 'recent': <Object?>[], 'agents': <Object?>[], 'settings': {..._settings, 'is_owner': false, 'approvers': 'owner'}};
      }
      if (path.endsWith('/agent-actions')) return {'actions': [_pending]};
      return {'id': 'b1', 'my_role': 'manager'};
    });
    await _pump(tester, api, const AskodoxAgentInboxScreen(businessId: 'b1'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxAgentInboxOwnerOnly')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxAgentInboxApprove-a1')), findsNothing);
  });

  testWidgets('inbox: nothing waiting says so', (tester) async {
    final api = _Api((m, path, b) {
      if (path.endsWith('/agent-team')) return {'pending': 0, 'recent': <Object?>[], 'agents': <Object?>[], 'settings': _settings};
      if (path.endsWith('/agent-actions')) return {'actions': <Object?>[]};
      return {'id': 'b1', 'my_role': 'owner'};
    });
    await _pump(tester, api, const AskodoxAgentInboxScreen(businessId: 'b1'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('askodoxAgentInboxEmpty')), findsOneWidget);
  });

  testWidgets('history: rows show, the Stopped filter hides done ones', (tester) async {
    final done = {..._pending, 'id': 'a2', 'summary': 'Move follow-up', 'status': 'DONE', 'risk': 'safe'};
    final stopped = {..._pending, 'id': 'a3', 'summary': 'Close complaint', 'status': 'REJECTED'};
    final api = _Api((m, path, b) {
      if (path.endsWith('/agent-settings')) return _settings;
      return {'actions': [done, stopped]};
    });
    await _pump(tester, api, const AskodoxAgentLogScreen(businessId: 'b1'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('askodoxAgentLogRow-a2')), findsOneWidget);
    expect(find.byKey(const ValueKey('askodoxAgentLogRow-a3')), findsOneWidget);
    await tester.tap(find.byKey(const Key('askodoxStepToggle-stopped')));
    await tester.pump();
    expect(find.byKey(const ValueKey('askodoxAgentLogRow-a2')), findsNothing);
    expect(find.byKey(const ValueKey('askodoxAgentLogRow-a3')), findsOneWidget);
  });

  testWidgets('settings: the owner switches an agent off and picks who may approve', (tester) async {
    final api = _Api((m, path, b) => _settings);
    await _pump(tester, api, const AskodoxAgentSettingsScreen(businessId: 'b1'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('askodoxAgentSettingsSwitch-sales')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.calls['PUT /api/pos/businesses/b1/agent-settings'], {'agents_off': ['sales']});
    await tester.tap(find.byKey(const Key('askodoxStepToggle-owner')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.calls['PUT /api/pos/businesses/b1/agent-settings'], {'approvers': 'owner'});
  });

  testWidgets('settings: a non-owner can read but not change', (tester) async {
    final api = _Api((m, path, b) => {..._settings, 'is_owner': false});
    await _pump(tester, api, const AskodoxAgentSettingsScreen(businessId: 'b1'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(const ValueKey('askodoxAgentSettingsSwitch-sales')), warnIfMissed: false);
    await tester.tap(find.byKey(const Key('askodoxStepToggle-owner')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.calls.keys.where((k) => k.startsWith('PUT')), isEmpty);
  });
}
