import 'dart:async';

import 'package:erp_client/ui/workspace_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/module_browser.dart';
import 'package:erp_client/erp_models.dart';

Widget browser(RecordLoader loader, {VoidCallback? onCreate}) => MaterialApp(
  home: Scaffold(
    body: ModuleBrowser(
      module: ErpModule.stock,
      company: 'Example',
      currency: 'INR',
      loader: loader,
      onRecord: (_) {},
      onCreate: onCreate ?? () {},
      onBrowseAll: () {},
    ),
  ),
);

void main() {
  testWidgets('same-view refresh keeps rows and scroll through a failed read', (
    t,
  ) async {
    Completer<List<ErpRecord>>? pending;
    await t.pumpWidget(
      browser(
        (_, _) =>
            pending?.future ??
            Future.value(
              List.generate(
                50,
                (i) => ErpRecord({'name': 'ITEM-$i'}, ErpModule.stock),
              ),
            ),
      ),
    );
    await t.pumpAndSettle();
    final list = find.byType(ListView);
    await t.drag(list, const Offset(0, -500));
    await t.pumpAndSettle();
    final position = t
        .state<ScrollableState>(
          find.descendant(of: list, matching: find.byType(Scrollable)),
        )
        .position;
    final offset = position.pixels;
    pending = Completer<List<ErpRecord>>();
    await t.tap(find.byTooltip('Refresh records').first);
    await t.pump();
    expect(find.byType(ListView), findsOneWidget);
    expect(position.pixels, offset);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    pending.completeError(const FormatException('Refresh unavailable'));
    await t.pumpAndSettle();
    expect(find.byType(ListView), findsOneWidget);
    expect(find.textContaining('Refresh unavailable'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(position.pixels, offset);
  });

  testWidgets('superseded search results cannot replace the latest query', (
    t,
  ) async {
    final slow = Completer<List<ErpRecord>>();
    await t.pumpWidget(
      browser((query, _) async {
        if (query == 'old') return slow.future;
        return [
          ErpRecord({
            'name': query.isEmpty ? 'Initial' : 'Newest',
          }, ErpModule.stock),
        ];
      }),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'old');
    await t.pump(const Duration(milliseconds: 400));
    await t.enterText(find.byType(TextField), 'new');
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
    slow.complete([
      ErpRecord({'name': 'Outdated'}, ErpModule.stock),
    ]);
    await t.pumpAndSettle();
    expect(find.text('Newest'), findsWidgets);
    expect(find.text('Outdated'), findsNothing);
  });

  testWidgets(
    'read-only module offers a way back to records without creation prompts',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModuleBrowser(
              module: ErpModule.stock,
              company: 'Example',
              currency: 'INR',
              loader: (_, _) async => [],
              onRecord: (_) {},
              onCreate: null,
              onBrowseAll: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create record'), findsNothing);
      expect(find.textContaining('New'), findsNothing);
      expect(find.text('Refresh'), findsOneWidget);
    },
  );
  testWidgets(
    'manufacturing quantities use the item unit from the work order',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModuleBrowser(
              module: ErpModule.manufacturing,
              company: 'Example',
              currency: 'INR',
              loader: (_, _) async => [
                ErpRecord({
                  'name': 'WO-1',
                  'qty': 2.5,
                  'stock_uom': 'Kg',
                }, ErpModule.manufacturing),
              ],
              onRecord: (_) {},
              onCreate: null,
              onBrowseAll: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkspaceArt), findsOneWidget);
      expect(
        tester.widget<WorkspaceArt>(find.byType(WorkspaceArt)).object.name,
        'assembly',
      );
      expect(find.text('2.5 Kg'), findsOneWidget);
      expect(ErpModule.manufacturing.fields, contains('stock_uom'));
      expect(ErpRecord({'name': 'INV-1'}, ErpModule.accounts).amount, isNull);
    },
  );
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
    var created = false;
    await tester.pumpWidget(
      browser((query, start) async => [], onCreate: () => created = true),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('Create record').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Create record'));
    expect(created, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'a company replacement cancels its pending search and rejects old rows',
    (t) async {
      final pending = Completer<List<ErpRecord>>();
      final reads = <(String, String, int)>[];
      Widget view(String company) => MaterialApp(
        home: Scaffold(
          body: ModuleBrowser(
            module: ErpModule.stock,
            company: company,
            currency: 'INR',
            loader: (query, start) {
              reads.add((company, query, start));
              return company == 'Old company'
                  ? pending.future
                  : Future.value([
                      ErpRecord({'name': 'NEW-COMPANY-ITEM'}, ErpModule.stock),
                    ]);
            },
            onRecord: (_) {},
            onCreate: null,
            onBrowseAll: () {},
          ),
        ),
      );
      await t.pumpWidget(view('Old company'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'obsolete search');
      await t.pump(const Duration(milliseconds: 100));
      await t.pumpWidget(view('New company'));
      await t.pumpAndSettle();
      pending.complete([
        ErpRecord({'name': 'OLD-COMPANY-ITEM'}, ErpModule.stock),
      ]);
      await t.pumpAndSettle();
      expect(reads, [('Old company', '', 0), ('New company', '', 0)]);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('NEW-COMPANY-ITEM'), findsWidgets);
      expect(find.text('OLD-COMPANY-ITEM'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
