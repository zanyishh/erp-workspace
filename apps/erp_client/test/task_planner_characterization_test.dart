import 'dart:async';

import 'package:erp_client/erp_api.dart';
import 'package:erp_client/document_editor.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:erp_client/task_planner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TaskApi extends ErpApi {
  _TaskApi() : super(Uri.parse('http://localhost:8081'));
  final calls = <(String, String?, String?, int)>[];
  Future<Map<String, dynamic>> Function(String, int)? respond;

  @override
  Future<Map<String, dynamic>> taskView(
    String company, {
    String? month,
    String? status,
    int start = 0,
  }) async {
    calls.add((company, month, status, start));
    return respond?.call(company, start) ?? _page(company, more: false);
  }

  @override
  Future<NativeSchema> nativeSchema(String doctype) async =>
      NativeSchema.fromJson({'doctype': doctype, 'fields': <dynamic>[]});

  @override
  Future<NativeDocument> nativeDocument(
    String doctype, {
    String? name,
    String? company,
    String? treeParent,
  }) async => NativeDocument.fromJson({
    'doc': {'doctype': doctype, 'name': name, 'company': company},
    'permissions': {'read': 1},
  });
}

Map<String, dynamic> _page(
  String label, {
  bool more = true,
  List<Map<String, dynamic>>? rows,
}) => {
  'statuses': ['Open', 'Working'],
  'has_more': more,
  'rows': rows ?? [_row('TASK-$label', label)],
};

Map<String, dynamic> _row(String name, String label) => {
  'name': name,
  'subject': label,
  'status': 'Open',
  'exp_start_date': '2031-04-01',
  'exp_end_date': '2031-04-04',
};

void main() {
  Future<void> show(WidgetTester tester, _TaskApi api, String company) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPlanner(api: api, company: company),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'duplicate page IDs keep the first row and advance by raw offset',
    (tester) async {
      final api = _TaskApi();
      addTearDown(api.close);
      api.respond = (_, start) async => switch (start) {
        0 => _page('first'),
        1 => _page(
          'second',
          rows: [
            _row('TASK-first', 'duplicate'),
            _row('TASK-second', 'second'),
          ],
        ),
        _ => _page('third', more: false),
      };
      await show(tester, api, 'Synthetic');
      await tester.tap(find.text('Load more tasks (1 shown)'));
      await tester.pumpAndSettle();
      expect(find.text('first'), findsOneWidget);
      expect(find.text('duplicate'), findsNothing);
      expect(find.text('second'), findsOneWidget);
      await tester.tap(find.text('Load more tasks (2 shown)'));
      await tester.pumpAndSettle();
      expect(api.calls.map((call) => call.$4), [0, 1, 3]);
      expect(find.text('third'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('read failure shows retry and retry starts from the first page', (
    tester,
  ) async {
    final api = _TaskApi();
    addTearDown(api.close);
    var fail = true;
    api.respond = (_, _) async {
      if (fail) throw const ErpException('Synthetic offline');
      return _page('Recovered', more: false);
    };
    await show(tester, api, 'Synthetic');
    expect(find.text('Could not load tasks'), findsOneWidget);
    expect(find.text('Synthetic offline'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered'), findsOneWidget);
    expect(api.calls.map((call) => call.$4), [0, 0]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing the company rejects the old in-flight task page', (
    tester,
  ) async {
    final api = _TaskApi();
    addTearDown(api.close);
    final pending = Completer<Map<String, dynamic>>();
    api.respond = (company, _) => company == 'Old company'
        ? pending.future
        : Future.value(_page('New company', more: false));
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPlanner(api: api, company: 'Old company'),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPlanner(api: api, company: 'New company'),
      ),
    );
    await tester.pump();
    pending.complete(_page('Old company', more: false));
    await tester.pumpAndSettle();
    expect(find.text('New company'), findsOneWidget);
    expect(find.text('Old company'), findsNothing);
    expect(api.calls.map((call) => call.$1), ['Old company', 'New company']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('replacing the API rejects the old in-flight task page', (
    tester,
  ) async {
    final oldApi = _TaskApi(), newApi = _TaskApi();
    addTearDown(oldApi.close);
    addTearDown(newApi.close);
    final pending = Completer<Map<String, dynamic>>();
    oldApi.respond = (_, _) => pending.future;
    newApi.respond = (_, _) async => _page('New account', more: false);
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPlanner(api: oldApi, company: 'Synthetic'),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPlanner(api: newApi, company: 'Synthetic'),
      ),
    );
    await tester.pump();
    pending.complete(_page('Old account', more: false));
    await tester.pumpAndSettle();
    expect(find.text('New account'), findsOneWidget);
    expect(find.text('Old account'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an old company access refresh cannot hide the new company', (
    tester,
  ) async {
    final api = _TaskApi();
    addTearDown(api.close);
    api.publishContext(
      WorkspaceContext.fromJson({
        'company': 'Old company',
        'access_fingerprint': 'initial',
      }),
    );
    await show(tester, api, 'Old company');
    final pending = Completer<Map<String, dynamic>>();
    addTearDown(() {
      if (!pending.isCompleted) {
        pending.complete(_page('Old company', more: false));
      }
    });
    api.respond = (company, _) => company == 'Old company'
        ? pending.future
        : Future.value(_page('New company', more: false));
    api.publishContext(
      WorkspaceContext.fromJson({
        'company': 'Old company',
        'access_fingerprint': 'changed',
        'revision': 1,
      }),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: TaskPlanner(api: api, company: 'New company'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('New company'), findsOneWidget);
    expect(find.text('Refreshing your access…'), findsNothing);
    expect(find.text('Old company'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'opening a task uses the shared editor and Back refreshes the board',
    (tester) async {
      final api = _TaskApi();
      addTearDown(api.close);
      await show(tester, api, 'Synthetic');
      await tester.tap(find.text('Synthetic'));
      await tester.pumpAndSettle();
      final editor = tester.widget<DocumentEditor>(find.byType(DocumentEditor));
      expect(editor.name, 'TASK-Synthetic');
      expect(editor.company, 'Synthetic');
      expect(editor.doctype, 'Task');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Synthetic'), findsOneWidget);
      expect(api.calls.length, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
