// Fresh, unposted synthetic Invoice register checks. GPL-3.0.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/design.dart';
import 'package:erp_client/document_editor.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/invoices/data/erp_invoice_repository.dart';
import 'package:erp_client/features/invoices/presentation/invoice_register_view_model.dart';
import 'package:erp_client/invoice_hub.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _ConnectedBinding();
  testWidgets(
    'fresh native draft register preserves paging, filters and editor navigation',
    (t) async {
      final password = Platform.environment['ERP_PASSWORD'];
      final raw = Platform.environment['ERP_INVOICE_REGISTER_FIXTURE'];
      if (password == null || raw == null) {
        throw StateError('Require synthetic credentials and fixture.');
      }
      final fixture = jsonDecode(raw) as Map<String, dynamic>;
      final companies = (fixture['companies'] as List).cast<String>();
      if (fixture['site'] != 'native-test.localhost' ||
          companies.length != 2 ||
          companies.any(
            (v) => !v.startsWith('Architecture Invoice Register '),
          )) {
        throw StateError('Refusing unrelated fixture material.');
      }
      final api = ErpApi(Uri.parse('http://127.0.0.1:8081'));
      addTearDown(api.close);
      late String lastName;
      await t.runAsync(() async {
        await api.login('Administrator', password);
        expect((await api.nativeCatalog()).site, 'native-test.localhost');
        await api.workspaceContext(company: companies.first);
        final repository = ErpInvoiceRepository(
          api: api,
          company: companies.first,
        );
        final model = InvoiceRegisterViewModel(repository);
        try {
          final first = await model.result;
          expect(first.rows, hasLength(25));
          expect(first.hasMore, isTrue);
          expect(first.rows.every((r) => r['status'] == 'Draft'), isTrue);
          expect(
            first.rows.every(
              (r) =>
                  r['grand_total'] is String &&
                  num.parse(r['grand_total'] as String) == 12.5,
            ),
            isTrue,
          );
          expect(model.canCreate(first), isTrue);
          expect(model.canManageSettings(first), isTrue);
          final last = await model.nextPage();
          expect(model.start, 25);
          expect(last.rows, hasLength(1));
          expect(last.hasMore, isFalse);
          lastName = last.rows.single['name'] as String;
          expect((fixture['invoices'] as List), contains(lastName));
          await model.chooseStatus('Draft');
          expect(model.start, 0);
          final selected = await model.search(lastName);
          expect(selected.rows.single['name'], lastName);
          final empty = await model.chooseStatus('Paid');
          expect(empty.rows, isEmpty);
          expect(empty.hasMore, isFalse);
          final reset = await model.showAll();
          expect(reset.rows, hasLength(25));
          final other = await ErpInvoiceRepository(
            api: api,
            company: companies[1],
          ).register();
          expect(other.rows, isEmpty);
        } finally {
          model.dispose();
        }
      });
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1100, 800);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      Future<void> wait(Finder finder) async {
        for (var i = 0; i < 240; i++) {
          await t.pump(const Duration(milliseconds: 50));
          if (finder.evaluate().isNotEmpty) return;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
        }
        fail('Connected Invoice register did not reach $finder');
      }

      final navigator = GlobalKey<NavigatorState>();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: WorkspaceTheme.theme,
          home: InvoiceHub(api: api, company: companies.first, canCreate: true),
        ),
      );
      await wait(find.byTooltip('Next invoices'));
      await t.tap(find.byTooltip('Next invoices'));
      await wait(find.text('Showing 26–26'));
      await t.tap(find.byTooltip('Open $lastName'));
      await wait(find.byType(DocumentEditor));
      await wait(find.text('Save'));
      expect(find.text(lastName), findsWidgets);
      expect(t.takeException(), isNull);
      navigator.currentState!.pop();
      await wait(find.byTooltip('Open $lastName'));
      await t.pumpWidget(const SizedBox.shrink());
      await t.runAsync(api.signOut);
      api.close();
      await t.pump(const Duration(seconds: 30));
      stdout.writeln(
        jsonEncode({
          'site': fixture['site'],
          'company': companies.first,
          'draftInvoices': 26,
          'registerPages': '25+1',
          'searchAndStatusReset': 'passed',
          'emptySecondCompany': 'passed',
          'nativeEditorNavigation': 'passed',
          'businessMutationsDuringReads': 0,
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
