import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_forms.dart';
import 'package:erp_client/mill_overview.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _job = <String, dynamic>{
  'name': 'NATIVE-JOB-12',
  'source_reference': 'JOB/2026/12',
  'customer': 'PARTY-16',
  'customer_name': 'Readable customer',
  'modified': '2026-11-15 10:00:00.000000',
  'job_date': '2026-11-14',
  'due_date': '2026-11-21',
  'status': 'Running',
  'target_kg': '10.000',
};

class _CustomerApi extends ErpApi {
  _CustomerApi() : super(Uri.parse('http://localhost:8081'));
  Map<String, dynamic>? posted;
  bool projected = false;
  @override
  Future<Map<String, dynamic>> knittingLookup(
    String company,
    String entity,
    String query, {
    int start = 0,
    String? job,
  }) async => {
    'rows': [
      {..._job, if (projected) 'source_reference_display': '12/26'},
    ],
    'has_more': false,
  };
  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String requestId, {
    String? modified,
  }) async {
    posted = values;
    return {'event': 'EVENT-1', 'data': {}};
  }
}

void main() {
  testWidgets(
    'job register shows verified full reference and retains raw identity',
    (t) async {
      final row = {
        ..._job,
        'source_reference': '12',
        'source_reference_display': '12/26',
      };
      Map<String, dynamic>? selected;
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MillJobRegister(
              jobs: [row],
              onJob: (job) => selected = job,
              caption: 'Orders',
              empty: 'No jobs',
              showOutput: false,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.text('12/26'));
      expect(selected?['name'], 'NATIVE-JOB-12');
      expect(selected?['source_reference'], '12');
    },
  );
  for (final width in [390.0, 1280.0]) {
    testWidgets(
      'job register shows party names and retains source identity at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Map<String, dynamic>? selected;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MillJobRegister(
                jobs: [
                  _job,
                  {
                    ..._job,
                    'name': 'LEGACY-JOB',
                    'source_reference': '',
                    'customer': 'Legacy party ID',
                    'customer_name': '   ',
                  },
                ],
                onJob: (job) => selected = job,
                caption: 'Latest order dates first',
                empty: 'No jobs',
                showOutput: false,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Readable customer'), findsOneWidget);
        expect(find.text('PARTY-16'), findsNothing);
        expect(find.text('Legacy party ID'), findsOneWidget);
        expect(find.textContaining('2026-11-14'), findsNWidgets(2));
        expect(find.textContaining('Due 2026-11-21'), findsNWidgets(2));
        await tester.tap(find.text('JOB/2026/12'));
        expect(selected?['name'], 'NATIVE-JOB-12');
        expect(selected?['customer'], 'PARTY-16');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('job picker uses readable customer without replacing record ID', (
    tester,
  ) async {
    final api = _CustomerApi()..projected = true;
    addTearDown(api.close);
    Map<String, dynamic>? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await pickKnitRecord(context, api, 'Mill', 'Job');
              },
              child: const Text('Select job'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select job'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Readable customer'), findsOneWidget);
    expect(find.textContaining('PARTY-16'), findsNothing);
    await tester.tap(find.text('12/26'));
    await tester.pumpAndSettle();
    expect(selected?['name'], 'NATIVE-JOB-12');
    expect(selected?['customer'], 'PARTY-16');
  });

  testWidgets('entry heading shows party name and submits the original job', (
    tester,
  ) async {
    final api = _CustomerApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: KnittingCommandForm(
          api: api,
          workspace: WorkspaceContext.fromJson({
            'company': 'Mill',
            'knitting_enabled': true,
            'capabilities': ['jobs', 'lifecycle'],
          }),
          action: knitActions.firstWhere((a) => a.id == 'close_job'),
          job: _job,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Readable customer'), findsOneWidget);
    expect(find.textContaining('PARTY-16'), findsNothing);
    await tester.tap(find.text('Review entry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm & post'));
    await tester.pumpAndSettle();
    expect(api.posted?['job'], 'NATIVE-JOB-12');
    expect(api.posted?.containsKey('customer_name'), isFalse);
  });
}
