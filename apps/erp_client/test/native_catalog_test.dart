import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/native_catalog.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:erp_client/native_models.dart';

class _RecordApi extends ErpApi {
  _RecordApi() : super(Uri.parse('http://localhost:8081'));
  bool canCreate = true;
  bool noRows = false;
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
  }) async => noRows || query.isNotEmpty
      ? []
      : [
          {'name': 'ITEM-1', 'item_name': 'Cotton'},
        ];
}

void main() {
  testWidgets(
    'long custom names remain legible and distinct reports do not repeat a generic chart',
    (tester) async {
      tester.view.physicalSize = const Size(390, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const names = [
        'Stock Ageing',
        'Bank Reconciliation Statement',
        'Sales Analytics',
        'Custom quarterly reconciliation of externally supplied fabric',
      ];
      final catalog = NativeCatalog.fromJson({
        'version': 1,
        'types': [],
        'reports': [
          for (final name in names) {'name': name, 'module': 'Accounts'},
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: NativeCatalogView(
              catalog: catalog,
              onType: (_) {},
              onReport: (_) {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('Reports'));
      await tester.pumpAndSettle();
      final symbols = <IconData?>{};
      for (final name in names.take(3)) {
        final tile = tester.widget<ListTile>(
          find.widgetWithText(ListTile, name),
        );
        final icons = find.descendant(
          of: find.byWidget(tile.leading!),
          matching: find.byType(Icon),
        );
        symbols.add(tester.widget<Icon>(icons).icon);
      }
      expect(symbols.length, 3);
      expect(find.widgetWithText(ListTile, names.last), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'accounting records are distinguishable by their leading symbols',
    (tester) async {
      final names = [
        'Bank Account',
        'Journal Entry',
        'Payment Entry',
        'Sales Invoice',
      ];
      final catalog = NativeCatalog.fromJson({
        'version': 1,
        'reports': [],
        'types': [
          for (final name in names) {'name': name, 'module': 'Accounts'},
        ],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeCatalogView(catalog: catalog, onType: (_) {}),
          ),
        ),
      );
      final symbols = <IconData?>{};
      for (final name in names) {
        final tile = tester.widget<ListTile>(
          find.widgetWithText(ListTile, name),
        );
        final glyph = find.descendant(
          of: find.byWidget(tile.leading!),
          matching: find.byType(Icon),
        );
        expect(glyph, findsOneWidget, reason: name);
        symbols.add(tester.widget<Icon>(glyph).icon);
      }
      expect(symbols.length, names.length);
    },
  );
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
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Stock Balance'), findsOneWidget);
  });

  testWidgets(
    'record list recovers from an empty search without changing module',
    (tester) async {
      final api = _RecordApi();
      addTearDown(api.close);
      final type = (await api.nativeCatalog()).types.single;
      await tester.pumpWidget(
        MaterialApp(
          home: NativeRecordScreen(api: api, type: type),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Missing');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('Cotton'), findsOneWidget);
      api.noRows = true;
      await tester.tap(find.byTooltip('Refresh records'));
      await tester.pumpAndSettle();
      expect(find.text('Create item'), findsOneWidget);
    },
  );

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
