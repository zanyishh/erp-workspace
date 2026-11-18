import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_catalog.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/native_tree.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NativeType _type(String name) => NativeType.fromJson({
  'name': name,
  'module': 'Stock',
  'is_tree': 1,
  'create': 1,
});
WorkspaceContext _context(int revision) => WorkspaceContext.fromJson({
  'company': 'A',
  'companies': [
    {'name': 'A'},
    {'name': 'B'},
  ],
  'revision': revision,
});
String _label(String type, String? company, String? parent) =>
    '$company $type ${parent ?? 'root'}';
Map<String, dynamic> _tree(String type, String? company, String? parent) => {
  'nodes': [
    {
      'name': 'NODE-$company',
      'title': _label(type, company, parent),
      'modified': 'v1',
      'expandable': 0,
    },
  ],
  'has_more': false,
  'can_create': false,
  'can_rename': true,
  'can_delete': true,
};
NativeCatalog _catalog(String? company) => NativeCatalog.fromJson({
  'version': 1,
  'types': [
    {'name': 'Item', 'module': 'Stock'},
    {'name': 'Visible $company type', 'module': 'Stock'},
  ],
  'reports': [],
});

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081')) {
    publishContext(_context(1));
  }
  final reads = <(String, String?, String?, int)>[];
  final catalogReads = <String?>[];
  final changes = <(String, String, String?)>[];
  Completer<Map<String, dynamic>>? pendingTree;
  Completer<NativeCatalog>? pendingCatalog;
  @override
  Future<Map<String, dynamic>> nativeTree(
    String doctype, {
    String? parent,
    String? company,
    int start = 0,
  }) {
    reads.add((doctype, company, parent, start));
    return company == 'A' && pendingTree != null
        ? pendingTree!.future
        : Future.value(_tree(doctype, company, parent));
  }

  @override
  Future<NativeCatalog> nativeCatalog({String? company}) {
    catalogReads.add(company);
    return company == 'A' && pendingCatalog != null
        ? pendingCatalog!.future
        : Future.value(_catalog(company));
  }

  @override
  Future<List<Map<String, dynamic>>> nativeRecords(
    String doctype, {
    String query = '',
    int start = 0,
    String? company,
  }) async => [
    {
      'name': 'ROW-$company',
      'item_name': 'Visible record $company',
      'modified': 'v1',
    },
  ];
  @override
  Future<void> changeTreeRecord(
    String doctype,
    String name,
    String modified,
    String action, {
    String? company,
    String? newName,
  }) async {
    changes.add((action, name, company));
  }
}

Widget _hierarchy(
  _Api api, {
  String company = 'A',
  String type = 'Warehouse',
  String? parent,
}) => MaterialApp(
  home: NativeTreeScreen(
    api: api,
    type: _type(type),
    company: company,
    parent: parent,
  ),
);

void main() {
  for (final changed in ['company', 'type', 'parent']) {
    testWidgets('hierarchy replaces a pending read when its $changed changes', (
      t,
    ) async {
      final api = _Api()..pendingTree = Completer<Map<String, dynamic>>();
      addTearDown(api.close);
      await t.pumpWidget(_hierarchy(api));
      await t.pump();
      final company = changed == 'company' ? 'B' : 'A';
      final type = changed == 'type' ? 'Item Group' : 'Warehouse';
      final parent = changed == 'parent' ? 'PARENT-2' : null;
      // Only the initial response is delayed; replacement requests are fresh.
      final old = api.pendingTree!;
      api.pendingTree = null;
      await t.pumpWidget(
        _hierarchy(api, company: company, type: type, parent: parent),
      );
      old.complete(_tree('Warehouse', 'A', null));
      await t.pumpAndSettle();
      expect(api.reads, contains((type, company, parent, 0)));
      expect(find.text(_label(type, company, parent)), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }
  for (final replacement in ['company', 'API']) {
    testWidgets(
      'a hierarchy delete dialog cannot target a replacement $replacement',
      (t) async {
        final first = _Api(), second = replacement == 'API' ? _Api() : null;
        addTearDown(first.close);
        if (second != null) {
          addTearDown(second.close);
        }
        await t.pumpWidget(_hierarchy(first));
        await t.pumpAndSettle();
        await t.tap(find.byTooltip('Actions for NODE-A'));
        await t.pumpAndSettle();
        await t.tap(find.text('Delete'));
        await t.pumpAndSettle();
        await t.pumpWidget(_hierarchy(second ?? first, company: 'B'));
        await t.pumpAndSettle();
        final confirm = find.widgetWithText(FilledButton, 'Delete');
        if (confirm.evaluate().isNotEmpty) {
          await t.tap(confirm);
          await t.pumpAndSettle();
        }
        expect([...first.changes, ...?second?.changes], isEmpty);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final screen in ['catalog', 'records', 'hierarchy']) {
    testWidgets('an old $screen access refresh cannot hide a new company', (
      t,
    ) async {
      final api = _Api();
      addTearDown(api.close);
      Widget view(String company) => switch (screen) {
        'catalog' => MaterialApp(
          home: NativeCatalogScreen(api: api, company: company),
        ),
        'records' => MaterialApp(
          home: NativeRecordScreen(
            api: api,
            company: company,
            type: _type('Item'),
          ),
        ),
        _ => _hierarchy(api, company: company),
      };
      await t.pumpWidget(view('A'));
      await t.pumpAndSettle();
      if (screen == 'hierarchy') {
        api.pendingTree = Completer<Map<String, dynamic>>();
      } else {
        api.pendingCatalog = Completer<NativeCatalog>();
      }
      api.publishContext(_context(2));
      await t.pump();
      await t.pumpWidget(view('B'));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 10));
      }
      try {
        final title = switch (screen) {
          'catalog' => 'Visible B type',
          'records' => 'Visible record B',
          _ => _label('Warehouse', 'B', null),
        };
        expect(find.text(title), findsOneWidget);
      } finally {
        api.pendingTree?.complete(_tree('Warehouse', 'A', null));
        api.pendingCatalog?.complete(_catalog('A'));
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull);
    });
  }
}
