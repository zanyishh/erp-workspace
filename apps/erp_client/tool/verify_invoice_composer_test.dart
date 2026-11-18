// Fresh synthetic financial composer checks. GPL-3.0.
import 'dart:convert';
import 'dart:io';

import 'package:erp_client/design.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/features/invoices/data/erp_invoice_repository.dart';
import 'package:erp_client/features/invoices/data/invoice_composer_repository.dart';
import 'package:erp_client/features/invoices/models/invoice_compose.dart';
import 'package:erp_client/features/invoices/presentation/invoice_composer_view_model.dart';
import 'package:erp_client/invoice_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

/// Drop only the first completed business response; every request reaches the real server.
class _LostAckRepository implements InvoiceComposerRepository {
  _LostAckRepository(this.inner);
  final InvoiceComposerRepository inner;
  int writes = 0;
  String? preparedState;
  @override
  Object get identity => inner.identity;
  @override
  Object? get scope => inner.scope;
  @override
  String get company => inner.company;
  @override
  bool get supportsRecovery => inner.supportsRecovery;
  @override
  Future<InvoiceComposeDefaults> defaults() => inner.defaults();
  @override
  Future<InvoiceReview> review(Map<String, Object?> draft) =>
      inner.review(draft);
  @override
  Future<String> save(
    Map<String, Object?> draft,
    String requestId,
    String review,
  ) async {
    writes++;
    await inner.save(draft, requestId, review);
    throw const ErpException(
      'Synthetic response interruption after the real server save.',
    );
  }

  @override
  Future<InvoiceSaveStatus> prepare(String requestId) async {
    final value = await inner.prepare(requestId);
    preparedState = value.state;
    return value;
  }

  @override
  Future<InvoiceSaveStatus> status(String requestId, {bool close = false}) =>
      inner.status(requestId, close: close);
  @override
  Future<void> acknowledge(String requestId) => inner.acknowledge(requestId);
  @override
  Future<List<Map<String, dynamic>>> searchLinks(
    String doctype,
    String query,
  ) => inner.searchLinks(doctype, query);
  @override
  Future<void> setTemplate(String name, String templateId) =>
      inner.setTemplate(name, templateId);
}

void main() {
  _ConnectedBinding();
  testWidgets(
    'fresh composer reviews and recovers a real saved draft without another write',
    (t) async {
      final password = Platform.environment['ERP_PASSWORD'];
      final raw = Platform.environment['ERP_INVOICE_COMPOSER_FIXTURE'];
      if (password == null || raw == null) {
        throw StateError('Require synthetic credentials and fixture.');
      }
      final fixture = jsonDecode(raw) as Map<String, dynamic>;
      final companies = (fixture['companies'] as List).cast<String>();
      if (fixture['site'] != 'native-test.localhost' ||
          companies.length != 2 ||
          companies.any(
            (v) => !v.startsWith('Architecture Invoice Composer '),
          ) ||
          !(fixture['customer'] as String).startsWith(
            'Architecture composer customer ',
          ) ||
          !(fixture['item'] as String).startsWith(
            'Architecture composer service ',
          )) {
        throw StateError('Refusing unrelated fixture material.');
      }
      final api = ErpApi(Uri.parse('http://127.0.0.1:8081'));
      addTearDown(api.close);
      late InvoiceComposerViewModel model;
      late InvoiceDraftReceipt receipt;
      late int businessWrites;
      await t.runAsync(() async {
        await api.login('Administrator', password);
        expect((await api.nativeCatalog()).site, 'native-test.localhost');
        await api.workspaceContext(company: companies.first);
        final repository = _LostAckRepository(
          ErpInvoiceRepository(api: api, company: companies.first),
        );
        expect(repository.supportsRecovery, isTrue);
        model = InvoiceComposerViewModel(
          repository,
          newRequestId: () => fixture['requestId'] as String,
        );
        await model.loaded;
        model.changeCustomer(fixture['customer'] as String);
        model.changeDate(fixture['postingDate'] as String);
        model.changeLine(
          model.lines.single.id,
          item: fixture['item'] as String,
          qty: '2',
          rate: '12.50',
        );
        model.changeStyle('grove');
        expect(await model.review(), isTrue, reason: model.error);
        expect(num.parse(model.reviewed!.data['grand_total'].toString()), 25);
        expect(model.reviewed!.token, matches(RegExp(r'^[0-9a-f]{64}$')));
        var result = await model.save();
        if (repository.preparedState == 'prepared') {
          expect(result, isNull);
          expect(model.uncertain, isTrue);
          expect(model.prepared, isTrue);
          expect(repository.writes, 1);
          result = await model.checkSave();
          expect(repository.writes, 1);
        } else {
          expect(repository.preparedState, 'completed');
          expect(repository.writes, 0);
        }
        expect(result, isNotNull, reason: model.error);
        receipt = result!;
        businessWrites = repository.writes;
        final saved = await api.nativeDocument(
          'Sales Invoice',
          name: receipt.name,
          company: companies.first,
        );
        expect(saved.data['docstatus'], 0);
        expect(saved.data['customer'], fixture['customer']);
        expect(num.parse(saved.data['grand_total'].toString()), 25);
        final row = (saved.data['items'] as List).single as Map;
        expect(row['item_code'], fixture['item']);
        expect(num.parse(row['qty'].toString()), 2);
        expect(num.parse(row['rate'].toString()), 12.5);
        final second = await api.salesInvoices(companies[1]);
        expect(second['rows'], isEmpty);
      });
      addTearDown(model.dispose);
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(1100, 1400);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetPhysicalSize);
      final messenger = GlobalKey<ScaffoldMessengerState>();
      await t.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: messenger,
          theme: WorkspaceTheme.theme,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
      messenger.currentState!.showSnackBar(
        SnackBar(content: Text('Draft ${receipt.name} saved.')),
      );
      await t.pump();
      expect(find.text('Draft ${receipt.name} saved.'), findsOneWidget);
      await t.runAsync(() => model.acknowledge(receipt));
      await t.runAsync(() async {
        final pending = await api.pendingOperations(companies.first);
        expect(
          (pending['rows'] as List).where(
            (row) => (row as Map)['request_id'] == fixture['requestId'],
          ),
          isEmpty,
        );
      });
      await t.pumpWidget(
        MaterialApp(
          theme: WorkspaceTheme.theme,
          home: InvoiceComposer(api: api, company: companies.first),
        ),
      );
      Future<void> wait(bool Function() ready) async {
        for (var i = 0; i < 240; i++) {
          await t.pump(const Duration(milliseconds: 30));
          if (ready()) return;
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
        }
        fail('Connected composer did not reach the expected state.');
      }

      await wait(
        () => find
            .descendant(
              of: find.widgetWithText(TextButton, 'Invoice date'),
              matching: find.textContaining(RegExp(r'^20\d{2}-\d{2}-\d{2}$')),
            )
            .evaluate()
            .isNotEmpty,
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Customer'),
        fixture['customer'] as String,
      );
      await t.enterText(
        find.widgetWithText(TextFormField, 'Item or service'),
        fixture['item'] as String,
      );
      await t.enterText(find.widgetWithText(TextFormField, 'Quantity'), '2');
      await t.enterText(
        find.widgetWithText(TextFormField, 'Rate override'),
        '12.50',
      );
      await t.tap(find.text('Review invoice'));
      await wait(() => find.text('Invoice summary').evaluate().isNotEmpty);
      expect(find.text('INR 25.00'), findsWidgets);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
      await t.runAsync(api.signOut);
      api.close();
      await t.pump(const Duration(seconds: 30));
      stdout.writeln(
        jsonEncode({
          'site': fixture['site'],
          'serverReviewedTotal': '25.00',
          'draft': receipt.name,
          'businessWritesThisTrial': businessWrites,
          'durableRecoveryWithoutDuplicate': 'passed',
          'renderedConfirmationThenAcknowledgment': 'passed',
          'secondCompanyEmpty': 'passed',
          'publicComposerReviewUi': 'passed',
          'financialAndStockPostings': 0,
        }),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
