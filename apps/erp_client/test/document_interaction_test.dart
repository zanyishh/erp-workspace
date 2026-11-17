import 'dart:async';

import 'package:erp_client/document_editor.dart';
import 'package:erp_client/document_fields.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/ui/access_gate.dart';
import 'package:erp_client/workspace_context.dart';
import 'package:erp_client/native_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NativeSchema sections() => NativeSchema.fromJson({
  'doctype': 'Example',
  'fields': [
    {'fieldname': 'title', 'fieldtype': 'Data', 'label': 'Title', 'reqd': 1},
    {
      'fieldname': 'extra',
      'fieldtype': 'Section Break',
      'label': 'Extra details',
    },
    {'fieldname': 'reference', 'fieldtype': 'Data', 'label': 'Reference'},
    {
      'fieldname': 'private',
      'fieldtype': 'Data',
      'label': 'Private',
      'hidden': 1,
    },
  ],
});

Future<void> fields(
  WidgetTester tester,
  NativeSchema schema,
  Map<String, dynamic> data,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: StatefulBuilder(
            builder: (_, update) => DocumentFields(
              schema: schema,
              data: data,
              onChanged: () => update(() {}),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final type in ['Date', 'Time']) {
    testWidgets('access revocation before the $type picker builds closes it', (
      tester,
    ) async {
      final api = ErpApi(Uri.parse('http://localhost:8081'));
      addTearDown(api.close);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'access_fingerprint': 'before',
        }),
      );
      Object? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: AccessGate(
            api: api,
            revalidate: () async =>
                throw const ErpException('Access unavailable'),
            child: Scaffold(
              body: NativeScalarField(
                field: NativeField.fromJson({
                  'fieldname': 'scheduled',
                  'label': 'Scheduled',
                  'fieldtype': type,
                }),
                value: null,
                editable: true,
                onChanged: (value) => selected = value,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Choose Scheduled'));
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'access_fingerprint': 'revoked',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(find.byType(TimePickerDialog), findsNothing);
      expect(find.text('Check access again'), findsOneWidget);
      expect(selected, isNull);
    });
  }

  testWidgets(
    'access revocation closes a generic lookup without an explicit scope key',
    (tester) async {
      final api = ErpApi(Uri.parse('http://localhost:8081'));
      addTearDown(api.close);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'access_fingerprint': 'before',
        }),
      );
      Object? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: AccessGate(
            api: api,
            revalidate: () async =>
                throw const ErpException('Access unavailable'),
            child: Scaffold(
              body: NativeScalarField(
                field: NativeField.fromJson({
                  'fieldname': 'customer',
                  'label': 'Customer',
                  'fieldtype': 'Link',
                }),
                value: null,
                editable: true,
                linkType: 'Customer',
                onChanged: (value) => selected = value,
                onLink: (_, _, _) async => [
                  {'value': 'Restricted customer'},
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Find Customer'));
      await tester.pumpAndSettle();
      expect(find.text('Restricted customer'), findsOneWidget);
      api.publishContext(
        WorkspaceContext.fromJson({
          'company': 'Demo',
          'access_fingerprint': 'revoked',
        }),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close search'), findsNothing);
      expect(find.text('Restricted customer'), findsNothing);
      expect(find.text('Check access again'), findsOneWidget);
      expect(selected, isNull);
    },
  );

  testWidgets(
    'optional sections disclose retained values without exposing hidden fields',
    (tester) async {
      final data = <String, dynamic>{'title': 'Example'};
      await fields(tester, sections(), data);
      expect(find.widgetWithText(TextFormField, 'Reference'), findsNothing);
      await tester.tap(find.text('Extra details'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Reference'),
        'Keep this',
      );
      await tester.tap(find.text('Extra details'));
      await tester.pumpAndSettle();
      expect(find.text('Keep this'), findsNothing);
      await tester.tap(find.text('Show all sections'));
      await tester.pumpAndSettle();
      expect(find.text('Keep this'), findsOneWidget);
      expect(find.text('Private'), findsNothing);
      expect(find.widgetWithText(TextFormField, 'Title *'), findsOneWidget);
    },
  );

  testWidgets('explicit save reveals and focuses an invalid optional section', (
    tester,
  ) async {
    final meta = NativeSchema.fromJson({
      'doctype': 'Example',
      'fields': [
        {'fieldname': 'title', 'fieldtype': 'Data', 'label': 'Title'},
        {
          'fieldname': 'extra',
          'fieldtype': 'Section Break',
          'label': 'Extra details',
        },
        {'fieldname': 'qty', 'fieldtype': 'Float', 'label': 'Quantity'},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: NativeDocumentForm(
          schema: meta,
          initial: NativeDocument.fromJson({
            'doc': {'doctype': 'Example', '__islocal': 1, 'qty': 'oops'},
            'permissions': {'create': 1},
          }),
          onSave: (_, _) async => throw StateError('Invalid must not save'),
        ),
      ),
    );
    await tester.tap(find.text('Extra details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(
      find.descendant(
        of: find.widgetWithText(TextFormField, 'Quantity'),
        matching: find.byType(TextField),
      ),
    );
    expect(input.focusNode!.hasFocus, isTrue);
    expect(find.text('Review 1 field'), findsOneWidget);
    expect(find.text('oops'), findsOneWidget);
  });

  testWidgets('removing a row can restore the same identity and order', (
    tester,
  ) async {
    final first = <String, dynamic>{'name': 'ROW-1', 'item': 'First'};
    final middle = <String, dynamic>{'name': 'ROW-2', 'item': 'Middle'};
    final last = <String, dynamic>{'name': 'ROW-3', 'item': 'Last'};
    final data = <String, dynamic>{
      'company': 'Demo',
      'rows': [first, middle, last],
    };
    final meta = NativeSchema.fromJson({
      'doctype': 'Example',
      'fields': [
        {
          'fieldname': 'rows',
          'label': 'Rows',
          'fieldtype': 'Table',
          'options': 'Row',
        },
      ],
      'children': {
        'Row': {
          'doctype': 'Row',
          'fields': [
            {'fieldname': 'item', 'label': 'Item', 'fieldtype': 'Data'},
          ],
        },
      },
    });
    await fields(tester, meta, data);
    await tester.tap(find.byTooltip('Remove row 2'));
    await tester.pumpAndSettle();
    expect((data['rows'] as List).length, 2);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(data['rows'], [first, middle, last]);
    expect(identical((data['rows'] as List)[1], middle), isTrue);
    await tester.tap(find.byTooltip('Remove row 2'));
    await tester.pumpAndSettle();
    data['company'] = 'Other';
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((data['rows'] as List).length, 2);
  });

  testWidgets(
    'lookup debounces, disables previous matches, ignores old responses and retries the query',
    (tester) async {
      final pending = <String, Completer<List<Map<String, dynamic>>>>{};
      final calls = <String>[];
      Object? value;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeScalarField(
              field: NativeField.fromJson({
                'fieldname': 'customer',
                'label': 'Customer',
                'fieldtype': 'Link',
              }),
              value: value,
              editable: true,
              linkType: 'Customer',
              onChanged: (next) => value = next,
              onLink: (_, query, _) {
                calls.add(query);
                return (pending[query] = Completer()).future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Find Customer'));
      await tester.pump();
      pending['']!.complete([
        {'value': 'Initial'},
      ]);
      await tester.pumpAndSettle();
      final search = find.widgetWithText(TextField, 'Search records…');
      await tester.enterText(search, 'a');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.enterText(search, 'ab');
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, ['']);
      expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, 'Initial')).onTap,
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, ['', 'ab']);
      await tester.enterText(search, 'abc');
      await tester.pump(const Duration(milliseconds: 300));
      pending['abc']!.complete([
        {'value': 'Current'},
      ]);
      await tester.pumpAndSettle();
      pending['ab']!.complete([
        {'value': 'Outdated'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Current'), findsOneWidget);
      expect(find.text('Outdated'), findsNothing);
      await tester.enterText(search, 'broken');
      await tester.pump(const Duration(milliseconds: 300));
      pending['broken']!.completeError(StateError('Unavailable'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retry search'));
      await tester.pump();
      expect(calls.last, 'broken');
      pending['broken']!.complete([
        {'value': 'Recovered'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('broken'), findsOneWidget);
      await tester.tap(find.text('Recovered'));
      await tester.pumpAndSettle();
      expect(value, 'Recovered');
    },
  );

  testWidgets('a changed linked-record type closes its stale chooser', (
    tester,
  ) async {
    var type = 'Customer';
    late StateSetter update;
    Object? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return Scaffold(
              body: NativeScalarField(
                field: NativeField.fromJson({
                  'fieldname': 'party',
                  'label': 'Party',
                  'fieldtype': 'Dynamic Link',
                }),
                value: null,
                editable: true,
                linkType: type,
                onChanged: (v) => selected = v,
                onLink: (_, _, _) async => [
                  {'value': 'Old customer'},
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.tap(find.byTooltip('Find Party'));
    await tester.pumpAndSettle();
    update(() => type = 'Supplier');
    await tester.pumpAndSettle();
    expect(find.text('Old customer'), findsNothing);
    expect(find.byTooltip('Close search'), findsNothing);
    expect(selected, isNull);
  });

  testWidgets(
    'posting review uses only permitted server fields and invalidates changed revisions',
    (tester) async {
      final meta = NativeSchema.fromJson({
        'doctype': 'Example',
        'submittable': 1,
        'fields': [
          {'fieldname': 'company', 'label': 'Company', 'fieldtype': 'Link'},
          {'fieldname': 'customer', 'label': 'Customer', 'fieldtype': 'Link'},
          {'fieldname': 'total_qty', 'label': 'Quantity', 'fieldtype': 'Float'},
        ],
      });
      NativeDocument doc(String revision) => NativeDocument.fromJson({
        'doc': {
          'doctype': 'Example',
          'name': 'EX-1',
          'modified': revision,
          'company': 'Demo',
          'customer': 'Buyer',
          'total_qty': 12,
          'grand_total': 98765,
        },
        'permissions': {'write': 1, 'submit': 1},
      });
      var current = doc('v1');
      late StateSetter update;
      var writes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (_, setState) {
              update = setState;
              return NativeDocumentForm(
                schema: meta,
                initial: current,
                onSave: (_, _) async {
                  writes++;
                  return current;
                },
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();
      final review = find.byType(AlertDialog);
      expect(
        find.descendant(of: review, matching: find.textContaining('Buyer')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: review, matching: find.textContaining('12')),
        findsOneWidget,
      );
      expect(find.textContaining('98765'), findsNothing);
      update(() => current = doc('v2'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(writes, 0);
    },
  );
  testWidgets(
    'draft paper returns to the same submit review and follows print permission',
    (t) async {
      final schema = NativeSchema.fromJson({
        'doctype': 'Sales Invoice',
        'submittable': 1,
        'fields': [],
      });
      final nav = GlobalKey<NavigatorState>();
      var writes = 0;
      final previews = <Map<String, dynamic>>[];
      Future<void> showDraft(bool printable) async {
        final doc = NativeDocument.fromJson({
          'doc': {
            'doctype': 'Sales Invoice',
            'name': 'INV-ONE',
            'company': 'Demo',
            'modified': 'v1',
            'docstatus': 0,
          },
          'permissions': {'write': 1, 'submit': 1, 'print': printable},
        });
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: NativeDocumentForm(
              schema: schema,
              initial: doc,
              onSubmissionPreview: (draft) {
                previews.add(draft);
                nav.currentState!.push(
                  MaterialPageRoute<void>(
                    builder: (context) => Scaffold(
                      appBar: AppBar(title: const Text('Exact draft PDF')),
                    ),
                  ),
                );
              },
              onSave: (_, action) async {
                expect(action, 'Submit');
                writes++;
                return doc;
              },
            ),
          ),
        );
        await t.tap(find.text('Submit'));
        await t.pumpAndSettle();
      }

      await showDraft(false);
      expect(find.text('Preview draft PDF'), findsNothing);
      await t.tap(find.text('Keep editing'));
      await t.pumpAndSettle();
      await showDraft(true);
      await t.tap(find.text('Preview draft PDF'));
      await t.pumpAndSettle();
      expect(
        (
          previews.single['company'],
          previews.single['name'],
          previews.single['modified'],
        ),
        ('Demo', 'INV-ONE', 'v1'),
      );
      expect(find.text('Exact draft PDF'), findsOneWidget);
      expect(writes, 0);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(find.text('Submit Sales Invoice?'), findsOneWidget);
      expect(writes, 0);
      await t.tap(find.text('Submit document'));
      await t.pumpAndSettle();
      expect(writes, 1);
    },
  );
}
