import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/features/catalog/data/catalog_repository.dart';
import 'package:erp_client/features/catalog/data/native_tree_repository.dart';
import 'package:erp_client/features/catalog/data/erp_catalog_repository.dart';
import 'package:erp_client/features/catalog/models/catalog_models.dart';
import 'package:erp_client/features/catalog/presentation/catalog_browse_view_model.dart';
import 'package:erp_client/features/catalog/presentation/catalog_view_model.dart';
import 'package:erp_client/features/catalog/presentation/native_records_view_model.dart';
import 'package:erp_client/features/catalog/presentation/native_tree_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:erp_client/features/catalog/presentation/native_tree_view.dart';

NativeType _type(String name) => NativeType.fromJson({
  'name': name,
  'module': 'Stock',
  'create': true,
  'can_group': true,
});
NativeCatalog _catalog() => NativeCatalog.fromJson({
  'version': 1,
  'types': [
    {'name': 'Item', 'module': 'Stock', 'create': true, 'can_group': true},
    {'name': 'Customer', 'module': 'Selling', 'create': false},
    {
      'name': 'Preferences',
      'module': 'System',
      'create': true,
      'issingle': true,
    },
  ],
  'reports': [
    {'name': 'Accounts Receivable', 'module': 'Accounts'},
  ],
});
List<Map<String, dynamic>> _rows() => [
  {'name': 'ITEM-1', 'item_name': 'Cotton', 'modified': 'v1'},
];
NativeTreePage _treePage({String title = 'Node one'}) =>
    NativeTreePage.fromJson({
      'nodes': [
        {'name': 'NODE-1', 'title': title, 'modified': 'v1', 'expandable': 1},
      ],
      'has_more': true,
      'can_create': true,
      'can_rename': true,
      'can_delete': true,
    });

class _Api extends ErpApi {
  _Api() : super(Uri.parse('http://127.0.0.1:8081'));
  Future<List<Map<String, dynamic>>>? pendingRows;
  final calls = <Object>[];
  @override
  Future<NativeCatalog> nativeCatalog({String? company}) async => _catalog();
  @override
  Future<List<Map<String, dynamic>>> nativeRecords(
    String doctype, {
    String query = '',
    int start = 0,
    String? company,
  }) {
    calls.add(('records', doctype, company, query, start));
    return pendingRows ?? Future.value(_rows());
  }

  @override
  Future<Map<String, dynamic>> nativeTree(
    String doctype, {
    String? parent,
    String? company,
    int start = 0,
  }) async {
    calls.add(('tree', doctype, company, parent, start));
    return {
      'nodes': [
        {'name': 'NODE-1', 'title': 'Node one', 'modified': 'v1'},
      ],
      'has_more': false,
    };
  }

  @override
  Future<void> changeTreeRecord(
    String doctype,
    String name,
    String modified,
    String action, {
    String? company,
    String? newName,
  }) async {
    calls.add(('change', doctype, name, modified, action, company, newName));
  }

  @override
  Future<int> reclassifyMasters(
    String doctype,
    String company,
    List<Map<String, String>> records,
    String group,
  ) async {
    calls.add(('group', doctype, company, records, group));
    return records.length;
  }
}

mixin _Scope implements CatalogSource {
  Object owner = Object();
  Object? access = Object();
  @override
  Object get identity => owner;
  @override
  Object? get scope => access;
}

class _Records with _Scope implements CatalogRepository {
  int catalogs = 0;
  final reads = <(String, String, int)>[];
  final changes = <(String, List<Map<String, String>>, String)>[];
  Future<int>? changing;
  @override
  Future<CatalogSnapshot> catalog() async {
    catalogs++;
    return CatalogSnapshot.fromNative(_catalog());
  }

  @override
  Future<NativeRecordPage> records(
    String doctype, {
    String query = '',
    int start = 0,
  }) async {
    reads.add((doctype, query, start));
    return NativeRecordPage.fromRows(_rows());
  }

  @override
  Future<List<Map<String, dynamic>>> groups(
    String doctype,
    String groupType,
    String query,
  ) async => [];
  @override
  Future<int> reclassify(
    String doctype,
    List<Map<String, String>> records,
    String group,
  ) {
    changes.add((doctype, records, group));
    return changing ?? Future.value(records.length);
  }
}

class _Tree with _Scope implements NativeTreeRepository {
  String title = 'Node one';
  final reads = <(String, String?, int)>[];
  final changes = <(String, String, String, String, String?)>[];
  Future<void>? changing;
  @override
  Future<NativeTreePage> tree(
    String doctype, {
    String? parent,
    int start = 0,
  }) async {
    reads.add((doctype, parent, start));
    return _treePage(title: title);
  }

  @override
  Future<void> changeTree(
    String doctype,
    String name,
    String modified,
    String action, {
    String? newName,
  }) {
    changes.add((doctype, name, modified, action, newName));
    return changing ?? Future.value();
  }
}

void main() {
  testWidgets(
    'returning from navigation reloads after same-owner access revalidation',
    (t) async {
      final repository = _Tree()..title = 'Before navigation';
      final model = NativeTreeViewModel(
        repository,
        type: _type('Warehouse'),
        company: 'A',
      );
      addTearDown(model.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: NativeTreeView(
            model: model,
            protect: (child, _) => child,
            browse: (_) async {},
            open: (_) async {
              repository.access = Object();
              await model.reload();
              repository.title = 'After navigation';
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byTooltip('Actions for NODE-1'));
      await t.pumpAndSettle();
      await t.tap(find.text('Open record'));
      await t.pumpAndSettle();
      expect(repository.reads, hasLength(3));
      expect(find.text('After navigation'), findsOneWidget);
    },
  );

  test(
    'an unready catalog can be constructed without making a request',
    () async {
      final repository = _Records()..access = null;
      final model = CatalogViewModel(repository);
      await expectLater(model.result, throwsA(isA<ErpException>()));
      expect(repository.catalogs, 0);
      model.dispose();
    },
  );
  test(
    'an unready record register can be constructed without making a request',
    () async {
      final repository = _Records()..access = null;
      final model = NativeRecordsViewModel(
        repository,
        type: _type('Item'),
        company: 'A',
      );
      await expectLater(model.result, throwsA(isA<ErpException>()));
      expect(repository.reads, isEmpty);
      model.dispose();
    },
  );
  test(
    'an unready hierarchy can be constructed without making a request',
    () async {
      final repository = _Tree()..access = null;
      final model = NativeTreeViewModel(
        repository,
        type: _type('Warehouse'),
        company: 'A',
      );
      await expectLater(model.result, throwsA(isA<ErpException>()));
      expect(repository.reads, isEmpty);
      model.dispose();
    },
  );
  test('catalog snapshots isolate mutable source metadata and nested record values', () {
    final source = _catalog();
    final snapshot = CatalogSnapshot.fromNative(source);
    source.types.clear();
    source.reports.first['module'] = 'Changed';
    expect(snapshot.types, hasLength(3));
    expect(snapshot.reports.single['module'], 'Accounts');
    expect(() => snapshot.types.clear(), throwsUnsupportedError);
    expect(() => snapshot.reports.single.clear(), throwsUnsupportedError);
    final original = <Map<String, dynamic>>[
      {
        'name': 'ROW',
        'tags': ['original'],
      },
    ];
    final page = NativeRecordPage.fromRows(original);
    (original.single['tags'] as List).clear();
    expect(page.rows.single['tags'], ['original']);
    expect(
      () => (page.rows.single['tags'] as List).clear(),
      throwsUnsupportedError,
    );
  });
  test(
    'browse projection preserves creation and task-phrase/module filtering',
    () {
      final snapshot = CatalogSnapshot.fromNative(_catalog());
      final create = CatalogBrowseViewModel(
        snapshot,
        create: true,
        allowReports: false,
      );
      expect(create.types.map((t) => t.name), ['Item']);
      final browse = CatalogBrowseViewModel(snapshot, allowReports: true);
      browse.search('  WHO OWES US  ');
      browse.selectReports(true);
      expect(browse.reports.map((r) => r['name']), ['Accounts Receivable']);
      browse.search('');
      browse.selectModule('Stock');
      expect(browse.types.map((t) => t.name), ['Item']);
      expect(browse.reports, isEmpty);
      expect(
        browse.modules,
        containsAll(['Stock', 'Selling', 'System', 'Accounts']),
      );
    },
  );
  test('ERP repository preserves read cursors, company and optimistic mutation payloads', () async {
    final api = _Api();
    addTearDown(api.close);
    final repository = ErpCatalogRepository(api: api, company: 'A');
    await repository.records('Item', query: 'cotton', start: 50);
    await repository.tree('Warehouse', parent: 'ROOT', start: 100);
    await repository.changeTree(
      'Warehouse',
      'NODE-1',
      'v1',
      'rename',
      newName: 'Renamed',
    );
    await repository.reclassify('Item', [
      {'name': 'ITEM-1', 'modified': 'v1'},
    ], 'New group');
    expect(api.calls.take(3).toList(), [
      ('records', 'Item', 'A', 'cotton', 50),
      ('tree', 'Warehouse', 'A', 'ROOT', 100),
      ('change', 'Warehouse', 'NODE-1', 'v1', 'rename', 'A', 'Renamed'),
    ]);
    final group =
        api.calls.last
            as (String, String, String, List<Map<String, String>>, String);
    expect(
      (group.$1, group.$2, group.$3, group.$5),
      ('group', 'Item', 'A', 'New group'),
    );
    expect(group.$4, [
      {'name': 'ITEM-1', 'modified': 'v1'},
    ]);
  });
  for (final change in ['account', 'revision', 'readiness']) {
    test(
      'ERP catalog repository rejects delayed rows after $change replacement',
      () async {
        final pending = Completer<List<Map<String, dynamic>>>();
        final api = _Api()..pendingRows = pending.future;
        addTearDown(api.close);
        final repository = ErpCatalogRepository(api: api, company: 'A');
        final read = repository.records('Item');
        final rejected = expectLater(
          read,
          throwsA(
            isA<ErpException>().having(
              (e) => e.permissionDenied,
              'permission denied',
              isTrue,
            ),
          ),
        );
        if (change == 'account') {
          api.account = 'replacement@example.invalid';
        }
        if (change == 'revision') {
          api.accessRevision++;
        }
        if (change == 'readiness') {
          api.accessReady = false;
        }
        pending.complete(_rows());
        await rejected;
      },
    );
  }
  test('record model keeps selection snapshots and resets only search/page context', () async {
    final repository = _Records();
    final model = NativeRecordsViewModel(
      repository,
      type: _type('Item'),
      company: 'A',
    );
    await model.result;
    model.toggleSelecting();
    expect(model.toggle('ITEM-1', 'v1'), isTrue);
    final intent = model.prepareGroupChange()!;
    expect(intent.records, [
      {'name': 'ITEM-1', 'modified': 'v1'},
    ]);
    expect(() => intent.records.single.clear(), throwsUnsupportedError);
    await model.nextPage();
    expect(model.start, 50);
    await model.reload(query: '  cotton  ');
    expect(model.query, 'cotton');
    expect(model.start, 0);
    expect(model.selected, {'ITEM-1': 'v1'});
    model.dispose();
    expect(await model.applyGroup(intent, 'New group'), isNull);
    expect(repository.changes, isEmpty);
  });
  for (final changedScope in [false, true]) {
    test(
      'group writes remain serialized through revalidation with scope change $changedScope',
      () async {
        final pending = Completer<int>();
        final repository = _Records()..changing = pending.future;
        final model = NativeRecordsViewModel(
          repository,
          type: _type('Item'),
          company: 'A',
        );
        await model.result;
        model.toggleSelecting();
        model.toggle('ITEM-1', 'v1');
        final intent = model.prepareGroupChange()!;
        final writing = model.applyGroup(intent, 'New group');
        if (changedScope) {
          repository.access = Object();
        }
        await model.revalidate();
        expect(model.savingGroup, isTrue);
        expect(await model.applyGroup(intent, 'Another group'), isNull);
        expect(repository.changes, hasLength(1));
        pending.complete(1);
        await writing;
        expect(model.savingGroup, isFalse);
        model.dispose();
      },
    );
  }
  test('an issued group intent cannot write after access changes', () async {
    final repository = _Records();
    final model = NativeRecordsViewModel(
      repository,
      type: _type('Item'),
      company: 'A',
    );
    await model.result;
    model.toggleSelecting();
    model.toggle('ITEM-1', 'v1');
    final intent = model.prepareGroupChange()!;
    repository.access = Object();
    expect(await model.applyGroup(intent, 'New group'), isNull);
    expect(repository.changes, isEmpty);
    model.dispose();
  });
  test('tree model keeps type and parent while paging and checks its issued intent', () async {
    final repository = _Tree();
    final model = NativeTreeViewModel(
      repository,
      type: _type('Warehouse'),
      company: 'A',
      parent: 'ROOT',
    );
    final page = await model.result;
    await model.nextPage();
    await model.previousPage();
    expect(repository.reads, [
      ('Warehouse', 'ROOT', 0),
      ('Warehouse', 'ROOT', 50),
      ('Warehouse', 'ROOT', 0),
    ]);
    final intent = model.prepareChange(page.nodes.single, 'rename')!;
    expect(await model.change(intent, newName: 'Renamed'), isTrue);
    expect(repository.changes, [
      ('Warehouse', 'NODE-1', 'v1', 'rename', 'Renamed'),
    ]);
    model.dispose();
  });
  test(
    'an obsolete tree dialog cannot send a command after its scope changes',
    () async {
      final repository = _Tree();
      final model = NativeTreeViewModel(
        repository,
        type: _type('Warehouse'),
        company: 'A',
      );
      final page = await model.result;
      final intent = model.prepareChange(page.nodes.single, 'delete')!;
      repository.access = Object();
      expect(await model.change(intent), isFalse);
      expect(repository.changes, isEmpty);
      model.dispose();
    },
  );
  test('a hierarchy refresh cannot release an in-flight mutation', () async {
    final pending = Completer<void>();
    final repository = _Tree()..changing = pending.future;
    final model = NativeTreeViewModel(
      repository,
      type: _type('Warehouse'),
      company: 'A',
    );
    final page = await model.result;
    final intent = model.prepareChange(page.nodes.single, 'delete')!;
    final writing = model.change(intent);
    await model.reload();
    expect(model.changing, isTrue);
    expect(await model.change(intent), isFalse);
    expect(repository.changes, hasLength(1));
    pending.complete();
    expect(await writing, isTrue);
    model.dispose();
  });
}
