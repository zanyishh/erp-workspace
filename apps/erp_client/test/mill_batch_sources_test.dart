import 'package:erp_client/erp_api.dart';
import 'package:erp_client/knitting_models.dart';
import 'package:erp_client/mill_overview.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class BatchSourcesApi extends ErpApi {
  BatchSourcesApi() : super(Uri.parse('http://localhost:8081'));
  final calls = <String>[];
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
    calls.add(collection);
    return {
      'version': 1,
      'company': company,
      'collection': collection,
      'scope_job': null,
      'rows': [
        {
          'name': 'Synthetic-batch',
          'source_reference': 'Saved-order-8',
          'quantity_kg': '-0.200',
          'rolls': '0',
          'state': 'Awaiting review',
        },
      ],
      'page': {'start': start, 'limit': 100, 'has_more': false, 'total': 1},
    };
  }
}

void main() {
  testWidgets('overview opens separate exact signed fabric balances', (
    t,
  ) async {
    t.view.physicalSize = const Size(1440, 1100);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final api = BatchSourcesApi();
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MillOverview(
            api: api,
            snapshot: KnittingSnapshot('Synthetic Mill', {
              'jobs': [],
              'rolls': [],
              'events': [],
            }),
            workspace: WorkspaceContext.fromJson({
              'company': 'Synthetic Mill',
              'knitting_enabled': true,
              'setup_state': 'Active',
              'capabilities': ['overview', 'jobs', 'production'],
            }),
            onDestination: (_, {filter}) {},
            onJob: (_) {},
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Fabric batches'));
    await t.pumpAndSettle();
    expect(api.calls, ['batches']);
    expect(find.text('Saved-order-8'), findsOneWidget);
    expect(find.text('-0.2 kg · 0 rolls / PCS'), findsOneWidget);
    expect(find.text('Awaiting review'), findsOneWidget);
    expect(find.textContaining('1–1 of 1'), findsOneWidget);
    expect(find.text('Release'), findsNothing);
    expect(t.takeException(), isNull);
  });
}
