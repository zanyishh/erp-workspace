import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/native_catalog.dart';
import 'package:erp_client/native_models.dart';

void main() {
  testWidgets(
    'catalog searches the full permitted list and opens the selected type',
    (tester) async {
      final catalog = NativeCatalog.fromJson({
        'version': 1,
        'types': [
          {'name': 'Customer', 'module': 'Selling', 'create': 1},
          {'name': 'Stock Settings', 'module': 'Stock', 'issingle': 1},
          {
            'name': 'Maintenance Schedule',
            'module': 'Maintenance',
            'create': 1,
          },
        ],
        'reports': [],
      });
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NativeCatalogView(
              catalog: catalog,
              onType: (t) => selected = t.name,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Maintenance');
      await tester.pumpAndSettle();
      expect(find.text('Customer'), findsNothing);
      await tester.tap(find.text('Maintenance Schedule'));
      expect(selected, 'Maintenance Schedule');
      expect(tester.takeException(), isNull);
    },
  );
}
