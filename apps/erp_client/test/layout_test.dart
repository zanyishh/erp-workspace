import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/erp_models.dart';
import 'package:erp_client/overview.dart';
import 'package:erp_client/sign_in.dart';
import 'package:erp_client/design.dart';

void main() {
  testWidgets('compact sign-in supports larger text without clipping', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: WorkspaceTheme.theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: SignInScreen(
          connect: () => throw UnimplementedError(),
          onSignIn: (_, _) async {},
          onLicenses: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Enter workspace'));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'first sign-in asks only for credentials and identifies missing fields',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: SignInScreen(
            connect: () => throw UnimplementedError(),
            onSignIn: (_, _) async {
              calls++;
            },
            onLicenses: () {},
          ),
        ),
      );
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      expect(find.text('Create a company'), findsOneWidget);
      expect(find.text('Join with invitation'), findsOneWidget);
      await tester.ensureVisible(find.text('Enter workspace'));
      await tester.tap(find.text('Enter workspace'));
      await tester.pumpAndSettle();
      expect(find.textContaining('address'), findsNothing);
      expect(find.text('Enter your username.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      expect(calls, 0);
      await tester.enterText(fields.first, 'mill-worker');
      await tester.enterText(fields.last, 'synthetic');
      await tester.ensureVisible(find.text('Enter workspace'));
      await tester.tap(find.text('Enter workspace'));
      await tester.pumpAndSettle();
      expect(calls, 1);
    },
  );
  testWidgets(
    'a long company name leaves the primary action reachable at phone text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = false;
      await tester.pumpWidget(
        MaterialApp(
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!,
          ),
          home: Scaffold(
            body: OverviewScreen(
              data: const ErpSnapshot(
                company:
                    'South Coast Garments and Knitting Manufacturing Company',
                currency: 'INR',
              ),
              onModule: (_) {},
              onNew: () => opened = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('New document')).left, lessThan(60));
      await tester.tap(find.text('New document'));
      expect(opened, isTrue);
    },
  );
  for (final width in [390.0, 834.0, 1440.0]) {
    testWidgets(
      'overview works at $width without overflow and opens the selected module',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        ErpModule? selected;
        const data = ErpSnapshot(company: 'ERP Evaluation', currency: 'INR');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OverviewScreen(
                data: data,
                onModule: (m) => selected = m,
                onNew: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('ERP Evaluation'), findsOneWidget);
        final stock = find.bySemanticsLabel('Open Stock').first;
        await tester.ensureVisible(stock);
        expect(
          tester
              .getSemantics(stock)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        await tester.tap(stock);
        await tester.pumpAndSettle();
        expect(selected, ErpModule.stock);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'empty invoices show a truthful empty state instead of a made-up chart',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverviewScreen(
              data: const ErpSnapshot(
                company: 'Empty Company',
                currency: 'INR',
              ),
              onModule: (_) {},
              onNew: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('No posted invoices yet'), findsOneWidget);
    },
  );
}
