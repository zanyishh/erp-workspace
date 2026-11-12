import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/workspace_picker.dart';

void main() {
  testWidgets(
    'search, select and dismiss module menu without a disposed controller',
    (tester) async {
      ErpModule? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showWorkspacePicker(context, (m) => selected = m),
                child: const Text('Modules'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Modules'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Stock');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Stock'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(selected, ErpModule.stock);
      expect(find.text('Modules'), findsOneWidget);
    },
  );
}
