import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/workspace_picker.dart';

void main() {
  testWidgets(
    'workspace search stays usable above a phone keyboard at large text sizes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 620);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      ErpModule? chosen;
      await tester.pumpWidget(
        MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    showWorkspacePicker(c, (m) => chosen = m, onAll: () {}),
                child: const Text('Browse'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Browse'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), 'Stock');
      await tester.pumpAndSettle();
      final stock = find.widgetWithText(ListTile, 'Stock');
      await tester.scrollUntilVisible(
        stock,
        75,
        scrollable: find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      await tester.tap(stock);
      await tester.pumpAndSettle();
      expect(chosen, ErpModule.stock);
      expect(tester.takeException(), isNull);
    },
  );
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
      await tester.enterText(find.byType(TextField), 'unmatched name');
      await tester.pumpAndSettle();
      expect(find.text('No matching workspaces'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '  Item  ');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Stock'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(selected, ErpModule.stock);
      expect(find.text('Modules'), findsOneWidget);
    },
  );
}
