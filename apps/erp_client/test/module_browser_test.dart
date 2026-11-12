import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/module_browser.dart';
import 'package:erp_client/erp_models.dart';

Widget browser(RecordLoader loader) => MaterialApp(
  home: Scaffold(
    body: ModuleBrowser(
      module: ErpModule.stock,
      company: 'Example',
      currency: 'INR',
      loader: loader,
      onRecord: (_) {},
      onCreate: () {},
      onBrowseAll: () {},
    ),
  ),
);

void main() {
  testWidgets('search reloads the current module after typing settles', (
    tester,
  ) async {
    final requests = <String>[];
    await tester.pumpWidget(
      browser((query, start) async {
        requests.add('$query:$start');
        return [
          ErpRecord({
            'name': 'ITEM-1',
            'item_name': 'Cartons',
          }, ErpModule.stock),
        ];
      }),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Carton');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(requests, [':0', 'Carton:0']);
    expect(tester.takeException(), isNull);
  });
  testWidgets('an empty next page offers a path back to the first page', (
    tester,
  ) async {
    await tester.pumpWidget(
      browser(
        (query, start) async => start == 0
            ? List.generate(
                50,
                (i) => ErpRecord({'name': 'ITEM-$i'}, ErpModule.stock),
              )
            : [],
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('END OF LIST'), findsOneWidget);
    await tester.tap(find.text('Back to first page'));
    await tester.pumpAndSettle();
    expect(find.text('ITEM-0'), findsWidgets);
  });

  testWidgets('empty-state action can scroll into a short compact viewport', (
    tester,
  ) async {
    // Remaining module area after the app header and phone keyboard.
    tester.view.physicalSize = const Size(390, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(browser((query, start) async => []));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Create record'));
    await tester.tap(find.text('Create record'));
    expect(tester.takeException(), isNull);
  });
}
