import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/document_fields.dart';
import 'package:erp_client/native_models.dart';

void main() {
  testWidgets(
    'multiselect adds a linked record without replacing earlier choices',
    (tester) async {
      Object? value = ['Cash'];
      final field = NativeField.fromJson({
        'fieldname': 'account',
        'label': 'Account',
        'fieldtype': 'MultiSelectList',
        'options': 'Account',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, update) => NativeScalarField(
                field: field,
                value: value,
                editable: true,
                linkType: 'Account',
                onChanged: (selected) => update(() => value = selected),
                onLink: (_, _, _) async => [
                  {'value': 'Sales'},
                ],
              ),
            ),
          ),
        ),
      );
      expect(find.text('Cash'), findsOneWidget);
      await tester.tap(find.byTooltip('Find Account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sales'));
      await tester.pumpAndSettle();
      expect(value, ['Cash', 'Sales']);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Sales'), findsOneWidget);
    },
  );
}
