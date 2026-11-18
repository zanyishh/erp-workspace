import 'package:erp_client/erp_api.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/invoice_hub.dart';
import 'package:erp_client/knitting_workspace_layout.dart';
import 'package:erp_client/module_browser.dart';
import 'package:erp_client/native_catalog.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/overview.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RowsApi extends ErpApi {
  _RowsApi() : super(Uri.parse('http://localhost:8081'));
  List<String> names = ['ROW-1', 'ROW-2', 'ROW-3'];

  @override
  Future<Map<String, dynamic>> salesInvoices(
    String company, {
    String query = '',
    String status = 'All',
    int start = 0,
    int limit = 25,
  }) async => {
    'rows': [
      for (final name in names)
        {
          'name': name,
          'customer_name': 'Example customer',
          'posting_date': '2026-11-14',
          'status': 'Unpaid',
          'currency': 'INR',
          'precision': 2,
          'grand_total': '100.00',
          'can_print': false,
        },
    ],
    'statuses': ['All', 'Unpaid'],
    'has_more': false,
    'can_create': false,
  };

  @override
  Future<List<Map<String, dynamic>>> nativeRecords(
    String doctype, {
    String query = '',
    int start = 0,
    String? company,
  }) async => [
    for (final name in names)
      {'name': name, 'item_name': 'Item $name', 'modified': 'v1'},
  ];
}

Widget _list(String screen, _RowsApi api) => switch (screen) {
  'invoices' => InvoiceHub(api: api, company: 'Example', canCreate: false),
  'records' => NativeRecordScreen(
    api: api,
    company: 'Example',
    type: NativeType.fromJson({'name': 'Item', 'module': 'Stock'}),
  ),
  _ => Scaffold(
    body: ModuleBrowser(
      module: ErpModule.stock,
      company: 'Example',
      currency: 'INR',
      loader: (_, _) async => [
        for (final name in api.names)
          ErpRecord({'name': name, 'item_name': 'Item $name'}, ErpModule.stock),
      ],
      onRecord: (_) {},
      onCreate: null,
      onBrowseAll: () {},
    ),
  ),
};

void main() {
  for (final screen in ['invoices', 'module', 'records']) {
    for (final width in [360.0, 1100.0]) {
      testWidgets('$screen keeps row identity after reorder at width $width', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final api = _RowsApi();
        addTearDown(api.close);
        await tester.pumpWidget(MaterialApp(home: _list(screen, api)));
        await tester.pumpAndSettle();
        Finder row(String name) => find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey && (widget.key as ValueKey).value == name,
        );
        final first = row('ROW-1');
        final third = row('ROW-3');
        final firstElement = tester.element(first);
        final thirdElement = tester.element(third);
        expect(
          tester.getTopLeft(first).dy,
          lessThan(tester.getTopLeft(third).dy),
        );

        api.names = ['ROW-3', 'ROW-2', 'ROW-1'];
        final refresh = find.byTooltip(
          screen == 'invoices' ? 'Refresh invoices' : 'Refresh records',
        );
        await tester.tap(refresh.first);
        await tester.pumpAndSettle();
        expect(tester.element(first), same(firstElement));
        expect(tester.element(third), same(thirdElement));
        expect(
          tester.getTopLeft(third).dy,
          lessThan(tester.getTopLeft(first).dy),
        );

        api.names = ['ROW-1', 'ROW-2'];
        await tester.tap(refresh.first);
        await tester.pumpAndSettle();
        expect(third, findsNothing);
        expect(tester.element(first), same(firstElement));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final title in ['Invoices', 'BUSINESS OVERVIEW', 'Mill overview']) {
    testWidgets('$title exposes a level-one heading to mobile readers', (
      tester,
    ) async {
      final api = _RowsApi();
      addTearDown(api.close);
      final Widget screen = switch (title) {
        'Invoices' => _list('invoices', api),
        'BUSINESS OVERVIEW' => Scaffold(
          body: OverviewScreen(
            data: const ErpSnapshot(company: 'Example', currency: 'INR'),
            onModule: (_) {},
            onNew: () {},
          ),
        ),
        _ => KnittingWorkspaceLayout(
          workspace: WorkspaceContext.fromJson({
            'company': 'Example',
            'knitting_enabled': true,
            'capabilities': ['overview'],
          }),
          page: 'Overview',
          onDestination: (_) {},
          actions: const [],
          child: const SizedBox(),
        ),
      };
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: screen,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(find.text(title)).getSemanticsData().headingLevel,
          1,
        );
      } finally {
        semantics.dispose();
      }
    });
  }
}
