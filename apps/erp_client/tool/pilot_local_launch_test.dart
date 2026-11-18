// Exercise the real app entry point and its private local credential after setup.
// The only test bridge supplies macOS Application Support's location, normally
// returned by the sandboxed native runner. All business calls use local HTTP.
import 'dart:io';

import 'package:erp_client/main.dart';
import 'package:erp_client/invoice_hub.dart';
import 'package:erp_client/local_workspace.dart';
import 'package:erp_client/overview.dart';
import 'package:erp_client/knitting_screen.dart';
import 'package:erp_client/sign_in.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _ConnectedBinding();
  testWidgets(
    'fresh local launches keep General and Knitting companies separate without authentication screens',
    (t) async {
      expect(LocalWorkspace.enabled, isTrue);
      final home = Platform.environment['HOME']!;
      final support =
          '$home/Library/Containers/org.localerp.erpClient/Data/Library/Application Support';
      const channel = MethodChannel('org.localerp.workspace/local');
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (c) async => c.method == 'applicationSupport' ? support : null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1440, 1000);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      Future<void> wait(Finder finder) async {
        for (var n = 0; n < 400; n++) {
          await t.pump(const Duration(milliseconds: 60));
          expect(find.byType(SignInScreen), findsNothing);
          expect(find.text('Verify your sign-in'), findsNothing);
          if (finder.evaluate().isNotEmpty) return;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        fail(
          'Waiting for $finder: ${t.widgetList<Text>(find.byType(Text)).map((t) => t.data).whereType<String>().join(" | ")}',
        );
      }

      for (var i = 0; i < 2; i++) {
        await t.pumpWidget(const ErpWorkspaceApp());
        await wait(find.byType(OverviewScreen));
        final data = t.widget<OverviewScreen>(find.byType(OverviewScreen)).data;
        expect(data.company, 'Meridian Trading');
        expect(data.billed, greaterThanOrEqualTo(25600));
        expect(data.unpaidInvoices, greaterThanOrEqualTo(2));
        expect(find.text('Knitting workspace'), findsNothing);
        expect(find.byType(KnittingScreen), findsNothing);
        final invoices = i == 0
            ? find.text('Invoices').first
            : find.byTooltip('View all invoices');
        await t.ensureVisible(invoices);
        await t.tap(invoices);
        await wait(find.byType(InvoiceHub));
        await wait(find.text('Atlas Office Supplies'));
        await wait(find.text('Harbour Retail Studio'));
        final generalHub = t.widget<InvoiceHub>(find.byType(InvoiceHub));
        expect(generalHub.company, 'Meridian Trading');
        expect(
          generalHub.api.account,
          'local-general-owner@workspace.example.invalid',
        );
        expect(find.text('Kaveri Loomworks'), findsNothing);
        expect(find.text('Vaigai Cotton Traders'), findsNothing);
        await t.pageBack();
        await wait(find.byType(OverviewScreen));
        await t.tap(find.text('Meridian Trading').first);
        await wait(find.text('Choose company'));
        await t.tap(
          find.widgetWithText(SimpleDialogOption, 'Kaveri Loomworks'),
        );
        await wait(find.byType(KnittingScreen));
        await wait(find.text('Mill overview'));
        final mill = t.widget<KnittingScreen>(find.byType(KnittingScreen));
        expect(mill.workspace.company, 'Kaveri Loomworks');
        expect(mill.api.account, 'local-owner@workspace.example.invalid');
        await t.tap(find.text('Invoices').first);
        await wait(find.byType(InvoiceHub));
        await wait(find.text('Vaigai Cotton Traders'));
        expect(
          t.widget<InvoiceHub>(find.byType(InvoiceHub)).company,
          'Kaveri Loomworks',
        );
        expect(find.text('Atlas Office Supplies'), findsNothing);
        await t.pageBack();
        await wait(find.byType(KnittingScreen));
        await t.tap(find.text('General ERP'));
        await wait(find.byType(OverviewScreen));
        expect(
          t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
          'Kaveri Loomworks',
        );
        expect(find.text('Knitting workspace'), findsNothing);
        await t.tap(find.text('Kaveri Loomworks').first);
        await wait(find.text('Choose company'));
        await t.tap(
          find.widgetWithText(SimpleDialogOption, 'Meridian Trading'),
        );
        await wait(find.byType(OverviewScreen));
        expect(
          t.widget<OverviewScreen>(find.byType(OverviewScreen)).data.company,
          'Meridian Trading',
        );
        expect(find.byType(KnittingScreen), findsNothing);
        await t.tap(find.text('Invoices').first);
        await wait(find.byType(InvoiceHub));
        await wait(find.text('Atlas Office Supplies'));
        expect(
          t.widget<InvoiceHub>(find.byType(InvoiceHub)).api.account,
          'local-general-owner@workspace.example.invalid',
        );
        expect(find.text('Kaveri Loomworks'), findsNothing);
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 25));
        debugPrint(
          'Cold open ${i + 1}: ${data.company}, ${data.currency} ${data.billed} billed, ${data.unpaidInvoices} unpaid; separate Kaveri knitting account and Meridian invoice register reopened.',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
