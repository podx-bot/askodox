import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podx/core/api/api_client.dart';
import 'package:podx/core/api/api_models.dart';
import 'package:podx/features/intelligence/data/intelligence_repository.dart';
import 'package:podx/features/intelligence/presentation/intelligence_card.dart';
import 'package:podx/features/intelligence/presentation/intelligence_screens.dart';
import 'package:podx/features/smart_tools/domain/tool_intent_router.dart';
import 'package:podx/services/in_app_assistant_service.dart';

class _Client implements ApiClient {
  _Client(this.reply, {this.status});
  final Map<String, Object?> reply;
  final int? status;
  final paths = <String>[];
  final bodies = <Object?>[];

  Future<ApiResult<T>> _answer<T>(String path, Object? body) async {
    paths.add(path);
    bodies.add(body);
    if (status != null) {
      return ApiError(ApiFailure(ApiFailureType.validation, message: 'bad value', statusCode: status));
    }
    return ApiSuccess(reply as T);
  }

  @override
  Future<ApiResult<T>> get<T>(String path, {ApiRequestOptions options = const ApiRequestOptions()}) => _answer(path, null);

  @override
  Future<ApiResult<T>> post<T>(String path, {Object? body, ApiRequestOptions options = const ApiRequestOptions()}) =>
      _answer(path, body);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester, Widget child, _Client client) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [askodoxIntelligenceRepositoryProvider.overrideWithValue(AskodoxIntelligenceRepository(client))],
    child: MaterialApp(home: child),
  ));
  await tester.pumpAndSettle();
}

Map<String, Object?> _regime(String regime, int total) => {
      'regime': regime, 'total_tax': total, 'taxable_income': 1225000, 'year_label': 'Tax year 2026-27 (FY 2026-27)',
      'standard_deduction': 75000, 'deductions_used': 0, 'slab_tax': 63750, 'rebate': 38750, 'surcharge': 0,
      'cess': 1000, 'notes': ['Marginal relief: tax limited to the income above Rs 12,00,000.'],
      'sources': [
        {'title': 'Income Tax Department — Tax rates', 'url': 'https://www.incometaxindia.gov.in/w/tax-rates'},
      ],
      'verified_on': '2026-10-23', 'professional_note': 'Estimate for planning only.',
    };

void main() {
  test('assistant decision parses the intelligence card; older backends give none', () {
    final withCard = InAppAssistantDecision.fromJson({
      'reply': 'ok', 'domain': 'general', 'transactional': false, 'source': 'universal_ai',
      'intelligence': {'kind': 'income_tax', 'action': {'route': '/intel/tax'}},
    });
    expect(withCard.intelligence?['kind'], 'income_tax');
    final without = InAppAssistantDecision.fromJson({'reply': 'ok', 'domain': 'general', 'transactional': false});
    expect(without.intelligence, isNull);
  });

  test('Indian rupee grouping', () {
    expect(askodoxRupees(0), '₹0');
    expect(askodoxRupees(999), '₹999');
    expect(askodoxRupees(1275000), '₹12,75,000');
    expect(askodoxRupees(124800.4), '₹1,24,800');
  });

  test('explicit money tools open from chat; questions stay with the brain', () {
    expect(askodoxToolIntent('open the income tax calculator')?.route, '/intel/tax');
    expect(askodoxToolIntent('gst calculator')?.route, '/intel/gst');
    expect(askodoxToolIntent('scam checklist')?.route, '/intel/fraud');
    expect(askodoxToolIntent('how much income tax on 15 lakh salary?'), isNull);
    expect(askodoxToolIntent('is this upi call a scam'), isNull);
  });

  testWidgets('chat card shows facts, official sources, date and opens the tool', (tester) async {
    String? opened;
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AskodoxIntelligenceCard(
            te: false,
            onOpen: (route) => opened = route,
            intelligence: const {
              'kind': 'fraud',
              'title': 'Fraud & market reality',
              'scheme': {
                'title': 'Job / work-from-home scams',
                'warning_signs': ['Any fee for registration, training or a laptop.'],
                'verify': ['Never pay to get a job.'],
                'report': [
                  {'name': 'Cyber fraud helpline 1930 (call immediately after money is lost)'},
                ],
                'verified_on': '2026-10-23',
              },
              'action': {'route': '/intel/fraud/employment_scam', 'label': 'Full checklist'},
            },
          ),
        ),
      ),
    ));
    expect(find.text('Warning signs'), findsOneWidget);
    expect(find.textContaining('1930'), findsOneWidget);
    expect(find.text('Checked against official sources on 2026-10-23'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('askodoxIntelOpen-fraud')));
    expect(opened, '/intel/fraud/employment_scam');
  });

  testWidgets('income tax: compares regimes, highlights the lower one, shows sources', (tester) async {
    final client = _Client({
      'status': 'success',
      'comparison': {
        'new': _regime('new', 26000), 'old': _regime('old', 167440), 'lower_tax': 'new', 'difference': 141440,
        'switching_rule': 'Salaried taxpayers can choose every year.',
      },
    });
    await _pump(tester, const AskodoxIncomeTaxScreen(), client);
    await tester.tap(find.byKey(const Key('askodoxTaxCalculate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('askodoxIntelError')), findsOneWidget, reason: 'no income -> nothing sent');
    expect(client.paths, isEmpty);
    await tester.enterText(find.byKey(const Key('askodoxTaxSalary')), '1300000');
    await tester.tap(find.byKey(const Key('askodoxTaxCalculate')));
    await tester.pumpAndSettle();
    expect(client.paths.single, '/api/intel/tax/income');
    final body = client.bodies.single as Map;
    expect(body['regime'], 'compare');
    expect(body['salary_income'], 1300000);
    expect(body['year'], '2026-27');
    expect(find.text('₹26,000'), findsOneWidget);
    expect(find.text('Lower tax'), findsOneWidget);
    expect(find.text('Income Tax Department — Tax rates'), findsOneWidget);
  });

  testWidgets('a rejected value shows the server reason, not a crash', (tester) async {
    final client = _Client(const {}, status: 422);
    await _pump(tester, const AskodoxIncomeTaxScreen(), client);
    await tester.enterText(find.byKey(const Key('askodoxTaxSalary')), '100');
    await tester.tap(find.byKey(const Key('askodoxTaxCalculate')));
    await tester.pumpAndSettle();
    expect(find.text('bad value'), findsOneWidget);
  });

  testWidgets('scam checklist shows verify steps and official channels', (tester) async {
    final client = _Client({
      'status': 'success',
      'scheme': {
        'id': 'employment_scam', 'title': 'Job / work-from-home scams', 'how_it_works': 'Fees are demanded.',
        'normal_practice': 'Genuine employers do not charge fees to hire you.',
        'warning_signs': ['Any fee for registration.'], 'verify': ['Never pay to get a job.'],
        'evidence': ['Screenshots of chats.'],
        'report': [{'name': 'Cyber fraud helpline 1930', 'contact': '1930', 'url': 'https://cybercrime.gov.in'}],
        'consequence': 'Cheating offence.', 'safer_alternative': 'Apply through official career pages.',
        'verified_on': '2026-10-23',
      },
    });
    await _pump(tester, const AskodoxFraudDetailScreen(schemeId: 'employment_scam'), client);
    expect(client.paths.single, '/api/intel/fraud/employment_scam');
    expect(find.text('What is normal / legitimate'), findsOneWidget);
    expect(find.text('Cyber fraud helpline 1930'), findsOneWidget);
    expect(find.text('Reporting channels checked on 2026-10-23'), findsOneWidget);
  });
}
