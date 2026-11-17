import 'package:erp_client/document_editor.dart';
import 'package:erp_client/native_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

NativeSchema orderSchema({String boundary = 'Tab Break'}) =>
    NativeSchema.fromJson({
      'doctype': 'Purchase Order',
      'fields': [
        {
          'fieldname': 'supplier',
          'fieldtype': 'Data',
          'label': 'Supplier',
          'reqd': 1,
        },
        for (final name in ['Buyer', 'Reference', 'Account'])
          {
            'fieldname': name.toLowerCase(),
            'fieldtype': 'Data',
            'label': name,
            if (name == 'Account')
              'conditions': {
                'mandatory_depends_on': {'op': 'field', 'name': 'carrier'},
              },
          },
        {
          'fieldname': 'private',
          'fieldtype': boundary,
          'label': 'Private',
          'hidden': 1,
        },
        {
          'fieldname': 'secret',
          'fieldtype': 'Data',
          'label': 'Private note',
          'reqd': 1,
        },
        {'fieldname': 'delivery', 'fieldtype': boundary, 'label': 'Delivery'},
        for (final name in ['Freight', 'Carrier', 'Warehouse', 'Destination'])
          {'fieldname': name.toLowerCase(), 'fieldtype': 'Data', 'label': name},
      ],
    });

NativeDocument order(Map<String, dynamic> values) => NativeDocument.fromJson({
  'doc': {'doctype': 'Purchase Order', ...values},
  'permissions': {'create': 1, 'write': 1},
});

void main() {
  for (final (width, boundary) in [
    (390.0, 'Tab Break'),
    (1120.0, 'Section Break'),
  ]) {
    testWidgets(
      'new long form advances through visible groups at width $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 780);
        addTearDown(tester.view.reset);
        final schema = orderSchema(boundary: boundary);
        final writes = <Map<String, dynamic>>[];
        await tester.pumpWidget(
          MaterialApp(
            home: NativeDocumentForm(
              schema: schema,
              initial: order({'__islocal': 1}),
              onSave: (values, action) async {
                expect(action, 'Save');
                writes.add(schema.payload(values));
                return order({...values, '__islocal': 0, 'name': 'PO-1'});
              },
            ),
          ),
        );
        expect(find.text('Step 1 of 2'), findsOneWidget);
        expect(find.text('Freight'), findsNothing);
        expect(find.text('Private note *'), findsNothing);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Supplier is required.'), findsWidgets);
        final supplier = find.widgetWithText(TextFormField, 'Supplier *');
        await tester.enterText(supplier, 'Synthetic supplier');
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump();
        expect(tester.getBottomRight(find.text('Next')).dy, lessThan(500));
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Step 2 of 2'), findsOneWidget);
        expect(supplier, findsNothing);
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Freight'),
          'Ground',
        );
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic supplier'), findsOneWidget);
        expect(writes, isEmpty);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Ground'), findsOneWidget);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(writes.single['supplier'], 'Synthetic supplier');
        expect(writes.single['freight'], 'Ground');
        expect(writes.single.containsKey('secret'), isFalse);
        expect(find.text('PO-1'), findsOneWidget);
        expect(find.text('Step 2 of 2'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'saving returns to an earlier field newly required by another step',
    (tester) async {
      final schema = orderSchema();
      await tester.pumpWidget(
        MaterialApp(
          home: NativeDocumentForm(
            schema: schema,
            initial: order({'__islocal': 1, 'supplier': 'Synthetic supplier'}),
            onSave: (_, _) async =>
                throw StateError('Invalid form must not save'),
          ),
        ),
      );
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Carrier'),
        'Courier',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final field = find.widgetWithText(TextFormField, 'Account *');
      expect(find.text('Step 1 of 2'), findsOneWidget);
      expect(
        tester
            .widget<TextField>(
              find.descendant(of: field, matching: find.byType(TextField)),
            )
            .focusNode!
            .hasFocus,
        isTrue,
      );
      expect(find.text('Account is required.'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('large native tabs open at their first logical group', (
    tester,
  ) async {
    final schema = NativeSchema.fromJson({
      'doctype': 'Sales Order',
      'fields': [
        for (final section in ['Order details', 'Currency', 'Items']) ...[
          {
            'fieldname': section,
            'label': '$section settings',
            'fieldtype': 'Section Break',
          },
          for (var i = 0; i < 6; i++)
            {
              'fieldname': '${section}_$i',
              'fieldtype': 'Data',
              'label': '$section $i',
              'reqd': 1,
            },
        ],
        {'fieldname': 'terms', 'fieldtype': 'Tab Break', 'label': 'Terms'},
        {'fieldname': 'payment', 'fieldtype': 'Data', 'label': 'Payment terms'},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: NativeDocumentForm(
          schema: schema,
          initial: order({'__islocal': 1}),
          onSave: (_, _) async => throw StateError('No save'),
        ),
      ),
    );
    expect(find.text('Step 1 of 4'), findsOneWidget);
    expect(find.text('Order details 0 *'), findsOneWidget);
    expect(find.text('Items 0 *'), findsNothing);
    expect(find.text('New Sales Order'), findsOneWidget);
    expect(find.text('Sales Order'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Order details 0 *'),
      'Retained',
    );
    await tester.tap(find.text('Full form'));
    await tester.pumpAndSettle();
    expect(find.text('Items 0 *'), findsOneWidget);
    await tester.tap(find.text('Guided entry'));
    await tester.pumpAndSettle();
    expect(find.text('Retained'), findsOneWidget);
    expect(find.text('Items 0 *'), findsNothing);
  });

  testWidgets('existing and linked records keep the full editor', (
    tester,
  ) async {
    for (final values in [
      {'name': 'PO-1'},
      {
        '__islocal': 1,
        '__native_origin': {'doctype': 'Material Request'},
      },
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: NativeDocumentForm(
            key: UniqueKey(),
            schema: orderSchema(),
            initial: order(values),
            onSave: (_, _) async => throw StateError('No save'),
          ),
        ),
      );
      expect(find.text('Next'), findsNothing);
      expect(find.text('Save'), findsOneWidget);
      expect(find.text('Show all sections'), findsOneWidget);
    }
  });
}
