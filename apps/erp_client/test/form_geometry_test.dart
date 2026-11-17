import 'package:erp_client/design.dart';
import 'package:erp_client/document_fields.dart';
import 'package:erp_client/native_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('document fields align at desktop, phone and large text sizes', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final schema = NativeSchema.fromJson({
      'doctype': 'Synthetic invoice',
      'fields': [
        {'fieldname': 'party', 'label': 'Customer', 'fieldtype': 'Data'},
        {'fieldname': 'quantity', 'label': 'Quantity', 'fieldtype': 'Float'},
        {'fieldname': 'notes', 'label': 'Notes', 'fieldtype': 'Small Text'},
      ],
    });
    final values = <String, dynamic>{
      'party': 'Synthetic mill',
      'quantity': '12.75',
    };
    for (final (width, scale, paired) in [
      (960.0, 1.0, true),
      (375.0, 1.0, false),
      (960.0, 1.6, false),
    ]) {
      await tester.binding.setSurfaceSize(Size(width, 800));
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: DocumentFields(
                      schema: schema,
                      data: values,
                      onChanged: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Rect field(String key) => tester.getRect(find.byKey(ValueKey(key)));
      final party = field('party'),
          quantity = field('quantity'),
          notes = field('notes');
      if (paired) {
        expect(quantity.top, party.top);
        expect(quantity.left - party.right, closeTo(20, 0.01));
      } else {
        expect(quantity.left, party.left);
        expect(quantity.top, greaterThanOrEqualTo(party.bottom));
      }
      expect(notes.width, width - 32);
      final input = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const ValueKey('quantity')),
          matching: find.byType(EditableText),
        ),
      );
      expect(input.textAlign, TextAlign.end);
      expect(input.textInputAction, TextInputAction.next);
      expect(input.controller.text, '12.75');
      expect(tester.takeException(), isNull);
    }
  });
}
