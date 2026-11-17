import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/mill_overview.dart';
import 'package:erp_client/workspace_context.dart';

class _YarnApi extends ErpApi {
  _YarnApi() : super(Uri.parse('http://localhost:8081'));
  final requests = <Map<String, dynamic>>[];
  bool wrongState = false;
  @override
  Future<Map<String, dynamic>> knittingOverview(String company) async => {
    'version': 1,
    'company': company,
    'jobs': {'total': 302, 'running': 102},
    'balances': {'yarn_kg': '1449840.309', 'running_yarn_kg': '322367.215'},
    'rolls': {},
    'plans': {},
    'production': <dynamic>[],
  };
  @override
  Future<Map<String, dynamic>> knittingRegister(
    String company,
    String collection, {
    String? job,
    int start = 0,
    String query = '',
    String? state,
    String? productionDate,
    String? fromDate,
    String? toDate,
    String? customer,
    String? category,
  }) async {
    requests.add({'state': state, 'start': start});
    return {
      'version': 1,
      'company': company,
      'collection': collection,
      'scope_job': job,
      'state': wrongState ? 'Completed' : state,
      'from_date': fromDate,
      'to_date': toDate,
      'customer': customer,
      'category': category,
      'rows': [
        {
          'name': 'RUN-$start',
          'source_reference_display': 'Running $start',
          'customer': 'Synthetic customer',
          'status': 'Running',
          'balances': {'yarn_kg': '1.000'},
        },
      ],
      'page': {
        'start': start,
        'limit': 100,
        'total': 102,
        'has_more': start == 0,
      },
    };
  }
}

void main() {
  final workspace = WorkspaceContext.fromJson({
    'company': 'Demo',
    'knitting_enabled': true,
    'setup_state': 'Active',
    'capabilities': ['overview', 'jobs', 'materials'],
  });
  Future<_YarnApi> open(WidgetTester tester, Map<String, dynamic> data) async {
    tester.view.physicalSize = const Size(1440, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _YarnApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        home: Scaffold(
          body: MillOverview(
            api: api,
            snapshot: KnittingSnapshot('Demo', data),
            workspace: workspace,
            onDestination: (_, {filter}) {},
            onJob: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets(
    'running yarn uses the complete total and keeps the all-job total labelled',
    (tester) async {
      final api = await open(tester, {
        'pagination': <String, dynamic>{},
        'jobs': <dynamic>[],
      });
      expect(find.text('Yarn for running jobs'), findsOneWidget);
      expect(find.text('322,367.215 kg', findRichText: true), findsOneWidget);
      expect(find.text('All jobs: 1,449,840.309 kg'), findsOneWidget);
      await tester.tap(find.text('Yarn for running jobs'));
      await tester.pumpAndSettle();
      expect(api.requests, [
        {'state': 'Running', 'start': 0},
      ]);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(api.requests.last, {'state': 'Running', 'start': 100});
      expect(find.text('Running 100'), findsOneWidget);
    },
  );

  testWidgets(
    'recent snapshot running balance and drilldown exclude completed jobs',
    (tester) async {
      await open(tester, {
        'jobs': [
          {
            'name': 'OPEN',
            'status': 'Running',
            'balances': {'yarn_kg': '2.125'},
          },
          {
            'name': 'CLOSED',
            'status': 'Completed',
            'balances': {'yarn_kg': '7.875'},
          },
        ],
      });
      expect(find.text('2.125 kg', findRichText: true), findsOneWidget);
      expect(find.text('Recent jobs: 10 kg'), findsOneWidget);
      await tester.tap(find.text('Yarn for running jobs'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(
        find.descendant(of: dialog, matching: find.text('OPEN')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: dialog, matching: find.text('CLOSED')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'missing running-job total is unavailable rather than the all-job amount',
    (tester) async {
      await open(tester, {
        'jobs': <dynamic>[],
        'overview': {
          'jobs': {'total': 302, 'running': 102},
          'balances': {'yarn_kg': '1449840.309'},
          'rolls': {},
          'plans': {},
          'production': <dynamic>[],
        },
      });
      expect(find.text('Yarn for running jobs'), findsOneWidget);
      expect(find.text('Balance unavailable'), findsOneWidget);
      expect(find.text('1,449,840.309 kg', findRichText: true), findsNothing);
    },
  );

  testWidgets(
    'an original negative fractional balance keeps its sign and decimals',
    (tester) async {
      await open(tester, {
        'jobs': [
          {
            'name': 'ORIGINAL',
            'status': 'Running',
            'balances': {'yarn_kg': '-0.125'},
          },
        ],
      });
      expect(find.text('-0.125 kg', findRichText: true), findsOneWidget);
    },
  );

  testWidgets(
    'running stock drilldown rejects a response for another job state',
    (tester) async {
      final api = await open(tester, {
        'pagination': <String, dynamic>{},
        'jobs': <dynamic>[],
      });
      api.wrongState = true;
      await tester.tap(find.text('Yarn for running jobs'));
      await tester.pumpAndSettle();
      expect(find.text('Running 0'), findsNothing);
      expect(find.textContaining('unexpected page'), findsOneWidget);
    },
  );
}
