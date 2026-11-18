import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/native_catalog.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_models.dart';

class HierarchyApi extends ErpApi {
  HierarchyApi() : super(Uri.parse('http://localhost:8081'));
  bool fail = false;
  bool create = true;
  bool manage = false;
  final changes = <String>[];
  @override
  Future<void> changeTreeRecord(
    String doctype,
    String name,
    String modified,
    String action, {
    String? company,
    String? newName,
  }) async {
    changes.add('$action $name $modified $company');
  }

  @override
  Future<List<Map<String, dynamic>>> nativeRecords(
    String doctype, {
    String query = '',
    int start = 0,
    String? company,
  }) async => [];

  @override
  Future<Map<String, dynamic>> nativeTree(
    String doctype, {
    String? parent,
    String? company,
    int start = 0,
  }) async {
    if (fail) throw const ErpException('Connection interrupted');
    if (doctype != 'Warehouse' || company != 'Test Company') {
      throw StateError('Tree context was lost');
    }
    return {
      'nodes': parent == null
          ? [
              {'name': 'ROOT', 'title': 'All warehouses', 'expandable': 1},
            ]
          : start == 0
          ? [
              {
                'name': 'STORES',
                'title': 'Stores',
                'expandable': 0,
                'modified': 'r1',
              },
            ]
          : [
              {'name': 'TRANSIT', 'title': 'Transit', 'expandable': 0},
            ],
      'has_more': parent != null && start == 0,
      'can_create': create,
      'can_delete': manage,
    };
  }

  @override
  Future<NativeSchema> nativeSchema(String doctype) async =>
      NativeSchema.fromJson({
        'doctype': 'Warehouse',
        'fields': [
          {
            'fieldname': 'warehouse_name',
            'label': 'Warehouse name',
            'fieldtype': 'Data',
          },
          {
            'fieldname': 'parent_warehouse',
            'label': 'Parent warehouse',
            'fieldtype': 'Data',
          },
        ],
      });

  @override
  Future<NativeDocument> nativeDocument(
    String doctype, {
    String? name,
    String? company,
    String? treeParent,
  }) async => NativeDocument.fromJson({
    'doc': {
      'doctype': 'Warehouse',
      'name': ?name,
      if (name == null) '__islocal': 1,
      'warehouse_name': name == null ? '' : 'Stores',
      'parent_warehouse': treeParent ?? 'ROOT',
    },
    'permissions': {'read': 1, 'create': 1, 'write': 1},
  });
}

void main() {
  late HierarchyApi api;
  setUp(() => api = HierarchyApi());
  tearDown(() => api.close());

  Future<void> openTree(WidgetTester tester, {bool compact = false}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeRecordScreen(
          api: api,
          company: 'Test Company',
          type: NativeType.fromJson({
            'name': 'Warehouse',
            'module': 'Stock',
            'is_tree': 1,
            'create': 1,
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (compact) {
      await tester.tap(find.byTooltip('Record actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Browse hierarchy'));
    } else {
      await tester.tap(find.byTooltip('Browse hierarchy'));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
    'hierarchy keeps company and parent while paging and opens a leaf natively',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await openTree(tester, compact: true);
      await tester.tap(find.text('All warehouses'));
      await tester.pumpAndSettle();
      expect(find.text('Stores'), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Transit'), findsOneWidget);
      expect(find.text('Stores'), findsNothing);
      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stores'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'Warehouse name'),
        findsOneWidget,
      );
      expect(find.text('Stores'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'destructive tree action requires confirmation for the selected record',
    (tester) async {
      api.manage = true;
      await openTree(tester);
      await tester.tap(find.text('All warehouses'));
      await tester.pumpAndSettle();
      Future<void> chooseDelete() async {
        await tester.tap(find.byTooltip('Actions for STORES'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
      }

      await chooseDelete();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.changes, isEmpty);
      await chooseDelete();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(api.changes, ['delete STORES r1 Test Company']);
    },
  );

  testWidgets('new child opens a native draft with the selected parent', (
    tester,
  ) async {
    await openTree(tester);
    await tester.tap(find.text('All warehouses'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New child'));
    await tester.pumpAndSettle();
    final parent = tester.widget<TextFormField>(
      find.widgetWithText(TextFormField, 'Parent warehouse'),
    );
    expect(parent.controller!.text, 'ROOT');
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'hierarchy failure can be retried and unavailable creation stays hidden',
    (tester) async {
      api.fail = true;
      api.create = false;
      await openTree(tester);
      expect(find.text('Connection interrupted'), findsOneWidget);
      api.fail = false;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('All warehouses'), findsOneWidget);
      expect(find.text('New'), findsNothing);
      expect(find.text('New child'), findsNothing);
    },
  );
}
