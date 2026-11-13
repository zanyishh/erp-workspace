import 'package:erp_client/design.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/overview.dart';
import 'package:erp_client/sales_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final record = ErpRecord({
    'name': 'INV-002',
    'customer_name': 'Example customer',
    'grand_total': 144.50,
    'currency': 'USD',
  }, ErpModule.accounts);
  final sample = ErpSnapshot(
    company: 'Example Co',
    currency: 'INR',
    billed: 94.25,
    sales: [
      SalesDay(DateTime(2026, 2, 1), 100.50),
      SalesDay(DateTime(2026, 2, 3), -6.25),
    ],
    activity: [record],
  );
  for (final reduced in [false, true]) {
    testWidgets(
      'chart handles missing days, credit notes and selection with reduced motion $reduced',
      (tester) async {
        ErpRecord? opened;
        await tester.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: child!,
            ),
            home: Scaffold(
              body: OverviewScreen(
                data: sample,
                range: DateRange(DateTime(2026, 2), DateTime(2026, 2, 5)),
                onModule: (_) {},
                onNew: () {},
                onRecord: (r) => opened = r,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('Feb 3, 2026 · -₹6.25'), findsOneWidget);
        final animation = find.descendant(
          of: find.byType(SalesChart),
          matching: find.byType(TweenAnimationBuilder<double>),
        );
        expect(
          tester.widget<TweenAnimationBuilder<double>>(animation).duration,
          Duration(milliseconds: reduced ? 0 : 180),
        );
        // Trigger the chart selection directly to measure its motion independently of button ink.
        final semantics = tester.widget<Semantics>(
          find.bySemanticsLabel('Daily sales chart'),
        );
        semantics.properties.onDecrease!();
        await tester.pump();
        expect(find.text('Feb 2, 2026 · ₹0'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 75));
        expect(tester.hasRunningAnimations, !reduced);
        await tester.pumpAndSettle();
        final chart = find.bySemanticsLabel('Daily sales chart');
        await tester.ensureVisible(chart);
        final rect = tester.getRect(chart);
        await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
        await tester.pumpAndSettle();
        expect(find.text('Feb 1, 2026 · ₹100.50'), findsOneWidget);
        Focus.of(
          tester.element(
            find
                .descendant(
                  of: find.byType(SalesChart),
                  matching: find.byType(GestureDetector),
                )
                .first,
          ),
        ).requestFocus();
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.text('Feb 2, 2026 · ₹0'), findsOneWidget);
        await tester.ensureVisible(find.text('Example customer'));
        await tester.tap(find.text('Example customer'));
        expect(opened, same(record));
        expect(find.text(r'$144.50'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'refresh keeps the inspected date within the same reporting period',
    (tester) async {
      Widget view(ErpSnapshot data) => MaterialApp(
        home: Scaffold(body: SalesChart(data: data)),
      );
      await tester.pumpWidget(view(sample));
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        view(
          ErpSnapshot(
            company: sample.company,
            currency: sample.currency,
            sales: [...sample.sales, SalesDay(DateTime(2026, 2, 4), 52)],
          ),
        ),
      );
      expect(find.text('Feb 2, 2026 · ₹0'), findsOneWidget);
    },
  );

  testWidgets('single credit note stays selectable on a large-text phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.6)),
          child: child!,
        ),
        home: Scaffold(
          body: OverviewScreen(
            data: ErpSnapshot(
              company: 'Example Co',
              currency: 'EUR',
              billed: -8.75,
              sales: [SalesDay(DateTime(2026, 4, 5), -8.75)],
            ),
            range: DateRange(DateTime(2026, 4, 5), DateTime(2026, 4, 6)),
            onModule: (_) {},
            onNew: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Apr 5, 2026 · -€8.75'), findsOneWidget);
    final steps = tester.widgetList<IconButton>(
      find.descendant(
        of: find.byType(SalesChart),
        matching: find.byType(IconButton),
      ),
    );
    expect(steps.map((step) => step.onPressed), [null, null]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'year range aggregates months and denied invoice access removes previously loaded values',
    (tester) async {
      Widget view(ErpSnapshot data) => MaterialApp(
        home: Scaffold(
          body: SalesChart(
            data: data,
            range: DateRange(DateTime(2026), DateTime(2026, 4)),
          ),
        ),
      );
      await tester.pumpWidget(view(sample));
      expect(find.text('Feb 2026 · ₹94.25'), findsOneWidget);
      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(find.text('Mar 2026 · ₹0'), findsOneWidget);
      await tester.pumpWidget(
        view(
          ErpSnapshot(
            company: 'Other',
            currency: 'INR',
            billed: null,
            sales: sample.sales,
          ),
        ),
      );
      expect(find.text('Invoice access unavailable'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
      expect(find.bySemanticsLabel('Monthly sales chart'), findsNothing);
    },
  );
}
