import 'package:erp_client/document_review.dart';
import 'package:erp_client/native_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final schema = NativeSchema.fromJson({
    'doctype': 'Sales Invoice',
    'fields': [
      {'fieldname': 'customer', 'label': 'Customer', 'fieldtype': 'Data'},
      {'fieldname': 'terms', 'label': 'Terms', 'fieldtype': 'Text Editor'},
      {
        'fieldname': 'items',
        'label': 'Items',
        'fieldtype': 'Table',
        'options': 'Item',
      },
      {
        'fieldname': 'other',
        'label': 'Other',
        'fieldtype': 'Table',
        'options': 'Unknown',
      },
      {'fieldname': 'amount', 'label': 'Total', 'fieldtype': 'Currency'},
    ],
    'children': {
      'Item': {
        'doctype': 'Item',
        'fields': [
          {'fieldname': 'qty', 'label': 'Quantity', 'fieldtype': 'Float'},
          {'fieldname': 'rate', 'label': 'Rate', 'fieldtype': 'Currency'},
        ],
      },
    },
  });
  final document = {
    'name': 'INV-001',
    'customer': 'Spinning & Knitting',
    'terms': '<p>Pack <strong>yarn &amp; cones</strong></p><script>privateScript()</script>',
    'items': [
      {'qty': '12.000', 'rate': '0.123456789', 'secret': 'Private child field'},
    ],
    'other': [
      {'hidden': 'Unprojected row value'},
    ],
    'amount': '1.481481468',
  };

  Future<void> review(WidgetTester t, Size size, double scale) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: AlertDialog(
            title: const Text('Submit Sales Invoice?'),
            content: DocumentReview(
              schema: schema,
              document: document,
              action: 'Submit',
            ),
            actions: [
              TextButton(
                onPressed: () {},
                child: const Text('Submit document'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets(
    'review renders rich text and never dumps unprojected child tables',
    (t) async {
      await review(t, const Size(1000, 800), 1);
      expect(
        find.text('Pack yarn & cones', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('privateScript', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('Private child field'), findsNothing);
      expect(find.textContaining('Unprojected row value'), findsNothing);
      expect(find.text('12.000'), findsOneWidget);
      expect(find.text('0.123456789'), findsOneWidget);
      expect(find.text('1.481481468'), findsOneWidget);
      expect(
        t.getTopLeft(find.text('Quantity')).dx,
        t.getTopLeft(find.text('Rate')).dx,
      );
      expect(
        t.getTopRight(find.text('12.000')).dx,
        t.getTopRight(find.text('0.123456789')).dx,
      );
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'narrow review stacks fields and keeps the confirmation reachable at large text',
    (t) async {
      await review(t, const Size(320, 640), 1.8);
      expect(
        t.getTopLeft(find.text('Spinning & Knitting')).dy,
        greaterThan(t.getTopLeft(find.text('Customer')).dy),
      );
      await t.ensureVisible(find.text('1.481481468'));
      await t.pumpAndSettle();
      expect(find.text('Submit document').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
}
