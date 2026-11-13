import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/native_catalog.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:erp_client/native_models.dart';

class _RecordApi extends ErpApi {
  _RecordApi() : super(Uri.parse('http://localhost:8081'));
  bool canCreate = true;
  @override
  Future<NativeCatalog> nativeCatalog({String? company}) async =>
      NativeCatalog.fromJson({
        'version': 1,
        'types': [
          {'name': 'Item', 'module': 'Stock', 'create': canCreate},
        ],
        'reports': [],
      });
  @override
  Future<List<Map<String, dynamic>>> nativeRecords(
    String doctype, {
    String query = '',
    int start = 0,
    String? company,
  }) async => [
    {'name': 'ITEM-1', 'item_name': 'Cotton'},
  ];
}

void main() {
  testWidgets(
    'catalog searches the full permitted list and opens the selected type',
    (tester) async {
      final catalog = NativeCatalog.fromJson({
        'version': 1,
        'types': [
          {'name': 'Customer', 'module': 'Selling', 'create': 1},
          {'name': 'Stock Settings', 'module': 'Stock', 'issingle': 1},
          {
            'name': 'Maintenance Schedule',
            'module': 'Maintenance',
            'create': 1,
          },
        ],
        'reports': [],
      });
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeCatalogView(
              catalog: catalog,
              onType: (t) => selected = t.name,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Maintenance');
      await tester.pumpAndSettle();
      expect(find.text('Customer'), findsNothing);
      await tester.tap(find.text('Maintenance Schedule'));
      expect(selected, 'Maintenance Schedule');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a module filter narrows records and reports together', (
    tester,
  ) async {
    final catalog = NativeCatalog.fromJson({
      'version': 1,
      'types': [
        {'name': 'Sales Invoice', 'module': 'Accounts'},
        {'name': 'Item', 'module': 'Stock'},
      ],
      'reports': [
        {'name': 'General Ledger', 'module': 'Accounts'},
        {'name': 'Stock Balance', 'module': 'Stock'},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NativeCatalogView(
            catalog: catalog,
            onType: (_) {},
            onReport: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Filter by module'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stock').last);
    await tester.pumpAndSettle();
    expect(find.text('Item'), findsOneWidget);
    expect(find.text('Sales Invoice'), findsNothing);
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Stock Balance'), findsOneWidget);
    expect(find.text('General Ledger'), findsNothing);
    await tester.enterText(find.byType(TextField), 'unmatched');
    await tester.pumpAndSettle();
    expect(find.text('No matching reports.'), findsOneWidget);
  });

  testWidgets('record list removes New when create permission is revoked', (
    tester,
  ) async {
    final api = _RecordApi();
    addTearDown(api.close);
    void publish(String fingerprint) => api.publishContext(
      WorkspaceContext.fromJson({
        'company': 'Demo',
        'access_fingerprint': fingerprint,
      }),
    );
    publish('before');
    final type = (await api.nativeCatalog()).types.single;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeRecordScreen(api: api, type: type, company: 'Demo'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New'), findsOneWidget);
    api.canCreate = false;
    publish('after');
    await tester.pumpAndSettle();
    expect(find.text('New'), findsNothing);
    expect(find.text('Cotton'), findsOneWidget);
  });
}
