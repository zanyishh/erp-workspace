import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/document_editor.dart';
import 'package:erp_client/document_fields.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/erp_api.dart';

NativeSchema schema() => NativeSchema.fromJson({
  'doctype': 'Example',
  'fields': [
    {'fieldname': 'title', 'label': 'Title', 'fieldtype': 'Data', 'reqd': 1},
    {
      'fieldname': 'locked',
      'label': 'Locked',
      'fieldtype': 'Data',
      'read_only': 1,
    },
  ],
});
NativeDocument draft() => NativeDocument.fromJson({
  'doc': {'doctype': 'Example', '__islocal': 1},
  'permissions': {'create': 1, 'write': 1},
});

void main() {
  testWidgets(
    'back immediately after typing protects the draft before the next frame',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => NativeDocumentForm(
                      schema: schema(),
                      initial: draft(),
                      onSave: (_, _) async => draft(),
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title *'),
        'Immediate back draft',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('This document has unsaved changes.'), findsOneWidget);
      expect(find.text('Immediate back draft'), findsOneWidget);
    },
  );

  testWidgets('item defaults populate a row and are kept only after Done', (
    tester,
  ) async {
    final data = <String, dynamic>{
      'rows': [
        {'doctype': 'Item Row', 'item_code': 'SERVICE', 'qty': 2, 'rate': 0},
      ],
    };
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentFields(
            schema: NativeSchema.fromJson({
              'doctype': 'Invoice',
              'fields': [
                {
                  'fieldname': 'rows',
                  'label': 'Items',
                  'fieldtype': 'Table',
                  'options': 'Item Row',
                },
              ],
              'children': {
                'Item Row': {
                  'doctype': 'Item Row',
                  'fields': [
                    {
                      'fieldname': 'item_code',
                      'label': 'Item',
                      'fieldtype': 'Data',
                      'reqd': 1,
                    },
                    {
                      'fieldname': 'qty',
                      'label': 'Quantity',
                      'fieldtype': 'Float',
                    },
                    {
                      'fieldname': 'rate',
                      'label': 'Rate',
                      'fieldtype': 'Currency',
                    },
                  ],
                },
              },
            }),
            data: data,
            onChanged: () => changes++,
            onItemDefaults: (parent, field, row) async => {...row, 'rate': 100},
          ),
        ),
      ),
    );
    await tester.tap(find.text('SERVICE · 2 · 0'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Load item details'));
    await tester.pumpAndSettle();
    expect(find.text('100'), findsOneWidget);
    expect((data['rows'] as List).single['rate'], 0);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect((data['rows'] as List).single['rate'], 100);
    expect(changes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('read only child rows open for viewing without changing data', (
    tester,
  ) async {
    final data = <String, dynamic>{
      'rows': [
        {'doctype': 'Row', 'description': 'Review details'},
      ],
    };
    var changes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentFields(
            schema: NativeSchema.fromJson({
              'doctype': 'Example',
              'fields': [
                {
                  'fieldname': 'rows',
                  'label': 'Rows',
                  'fieldtype': 'Table',
                  'options': 'Row',
                  'read_only': 1,
                },
              ],
              'children': {
                'Row': {
                  'doctype': 'Row',
                  'fields': [
                    {
                      'fieldname': 'description',
                      'label': 'Description',
                      'fieldtype': 'Data',
                    },
                  ],
                },
              },
            }),
            data: data,
            onChanged: () => changes++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review details'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Description'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    await tester.tap(find.byTooltip('Close row'));
    await tester.pumpAndSettle();
    expect(changes, 0);
  });

  testWidgets('workflow actions require saving dirty changes first', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeDocumentForm(
          schema: schema(),
          initial: NativeDocument.fromJson({
            'doc': {'doctype': 'Example', 'name': 'EX-1', 'title': 'Original'},
            'permissions': {'write': 1},
            'workflow': 'Approvals',
            'transitions': [
              {'action': 'Approve'},
            ],
          }),
          onSave: (_, _) async => throw StateError('No save expected'),
          onTransition: (_, _) async =>
              throw StateError('Dirty approval must be blocked'),
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title *'),
      'Changed before approval',
    );
    await tester.pump();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(
      find.text('Save your changes before applying a workflow action.'),
      findsOneWidget,
    );
    expect(find.text('Changed before approval'), findsOneWidget);
  });
  testWidgets('cancelled records cannot be edited or saved', (tester) async {
    final schema = NativeSchema.fromJson({
      'doctype': 'Example',
      'fields': [
        {'fieldname': 'title', 'label': 'Title', 'fieldtype': 'Data'},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: NativeDocumentForm(
          schema: schema,
          initial: NativeDocument.fromJson({
            'doc': {
              'doctype': 'Example',
              'name': 'EX-CANCEL',
              'docstatus': 2,
              'title': 'Cancelled',
            },
            'permissions': {'write': 1},
          }),
          onSave: (_, _) async =>
              throw StateError('Cancelled save should not be offered'),
        ),
      ),
    );
    expect(
      tester.widget<TextField>(find.byType(TextField).first).readOnly,
      isTrue,
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
  });

  testWidgets('back navigation keeps a dirty draft until discard is chosen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => NativeDocumentForm(
                    schema: schema(),
                    initial: draft(),
                    onSave: (_, _) async =>
                        throw StateError('No save in this scenario'),
                  ),
                ),
              ),
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title *'),
      'Unsaved title',
    );
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Keep your changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Unsaved title'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();
    expect(find.text('Open form'), findsOneWidget);
  });

  testWidgets(
    'create stays native and replaces draft with persisted name after save',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NativeDocumentForm(
            schema: schema(),
            initial: draft(),
            onSave: (values, action) async => NativeDocument.fromJson({
              'doc': {
                'doctype': 'Example',
                'name': 'EX-1001',
                'title': values['title'],
              },
              'permissions': {'write': 1},
            }),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title *'),
        'First native record',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('EX-1001'), findsOneWidget);
      expect(find.text('Saved successfully'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('server rejection preserves entered values', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NativeDocumentForm(
          schema: schema(),
          initial: draft(),
          onSave: (_, _) async =>
              throw const ErpException('Customer is disabled.'),
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title *'),
      'Keep these edits',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Customer is disabled.'), findsOneWidget);
    expect(find.text('Keep these edits'), findsOneWidget);
    expect(find.text('Saved successfully'), findsNothing);
  });

  testWidgets('pending save disables duplicate writes', (tester) async {
    final pending = Completer<NativeDocument>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NativeDocumentForm(
          schema: schema(),
          initial: draft(),
          onSave: (_, _) {
            calls++;
            return pending.future;
          },
        ),
      ),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title *'),
      'One write',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNull,
    );
    expect(calls, 1);
    pending.complete(
      NativeDocument.fromJson({
        'doc': {'doctype': 'Example', 'name': 'EX-1'},
        'permissions': {'write': 1},
      }),
    );
    await tester.pumpAndSettle();
    expect(find.text('EX-1'), findsOneWidget);
  });
}
