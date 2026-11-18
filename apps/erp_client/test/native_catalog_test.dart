import 'dart:async';

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
  Completer<List<Map<String, dynamic>>>? pending;
  final groups = <String>[];
  @override
  Future<int> reclassifyMasters(
    String doctype,
    String company,
    List<Map<String, String>> records,
    String group,
  ) async {
    expect(records, [
      {'name': 'ITEM-1', 'modified': 'v1'},
    ]);
    groups.add(group);
    return records.length;
  }

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
  }) async => pending != null
      ? pending!.future
      : noRows || query.isNotEmpty
      ? []
      : [
          {'name': 'ITEM-1', 'item_name': 'Cotton', 'modified': 'v1'},
        ];
}

void main() {
  testWidgets(
    'replacing the API clears query and rows even with the same company and account',
    (t) async {
      final first = _RecordApi();
      final second = _RecordApi()
        ..pending = Completer<List<Map<String, dynamic>>>();
      addTearDown(first.close);
      addTearDown(second.close);
      Widget screen(ErpApi api) => MaterialApp(
        home: NativeRecordScreen(
          api: api,
          company: 'Mill',
          type: NativeType.fromJson({'name': 'Item', 'module': 'Stock'}),
        ),
      );
      await t.pumpWidget(screen(first));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField), 'prior query');
      await t.pump(const Duration(milliseconds: 400));
      await t.pumpAndSettle();
      await t.pumpWidget(screen(second));
      await t.pump();
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('Cotton'), findsNothing);
      second.pending!.complete([
        {'name': 'ITEM-NEW', 'item_name': 'New scope cotton'},
      ]);
      await t.pumpAndSettle();
      expect(find.text('New scope cotton'), findsOneWidget);
    },
  );

  testWidgets('record refresh retains rows but permission denial clears them', (
    t,
  ) async {
    final api = _RecordApi();
    addTearDown(api.close);
    await t.pumpWidget(
      MaterialApp(
        home: NativeRecordScreen(
          api: api,
          company: 'Mill',
          type: NativeType.fromJson({'name': 'Item', 'module': 'Stock'}),
        ),
      ),
    );
    await t.pumpAndSettle();
    api.pending = Completer<List<Map<String, dynamic>>>();
    await t.tap(find.byTooltip('Refresh records'));
    await t.pump();
    expect(find.text('Cotton'), findsOneWidget);
    api.pending!.completeError(
      const ErpException('Access removed', permissionDenied: true),
    );
    await t.pumpAndSettle();
    expect(find.text('Cotton'), findsNothing);
    expect(find.text('Access removed'), findsOneWidget);
  });

  testWidgets('multiple-record selection posts only after group confirmation', (
    tester,
  ) async {
    final api = _RecordApi();
    addTearDown(api.close);
    await tester.pumpWidget(
      MaterialApp(
        home: NativeRecordScreen(
          api: api,
          company: 'Mill',
          type: NativeType.fromJson({
            'name': 'Item',
            'module': 'Stock',
            'can_group': true,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select records'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cotton'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Change group'));
    await tester.pumpAndSettle();
    final input = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(input, 'Fabric');
    await tester.pumpAndSettle();
    expect(api.groups, isEmpty);
    await tester.tap(find.text('Apply group'));
    await tester.pumpAndSettle();
    expect(api.groups, ['Fabric']);
    expect(find.byTooltip('Select records'), findsOneWidget);
  });
  testWidgets(
    'plain-language task searches keep the selected module and create permissions',
    (tester) async {
      final catalog = NativeCatalog.fromJson({
        'version': 1,
        'types': [
          {'name': 'Purchase Receipt', 'module': 'Stock', 'create': true},
          {'name': 'Sales Invoice', 'module': 'Accounts', 'create': false},
          {'name': 'Item', 'module': 'Stock', 'create': true},
        ],
        'reports': [],
      });
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeCatalogView(
              catalog: catalog,
              create: true,
              onType: (value) => selected = value.name,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'receive goods');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Purchase Receipt'));
      expect(selected, 'Purchase Receipt');
      await tester.enterText(find.byType(TextField), 'bill customer');
      await tester.pumpAndSettle();
      expect(find.text('Sales Invoice'), findsNothing);
    },
  );
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
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
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
