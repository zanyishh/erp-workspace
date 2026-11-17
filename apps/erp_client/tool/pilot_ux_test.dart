// Opt-in connected rehearsal. All mutations use synthetic native-test fixtures.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erp_client/design.dart';
import 'package:erp_client/document_editor.dart';
import 'package:erp_client/document_fields.dart';
import 'package:erp_client/erp_api.dart';
import 'package:erp_client/invoice_composer.dart';
import 'package:erp_client/main.dart';
import 'package:erp_client/native_models.dart';
import 'package:erp_client/pending_operations.dart';
import 'package:erp_client/knitting_forms.dart';

class _ConnectedBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

/// The server completes the real request; only its response is deliberately
/// dropped. The UI must reconcile the original receipt without a second write.
class _LostResponseApi extends ErpApi {
  _LostResponseApi(super.uri);
  bool dropInvoice = false, dropNative = false, dropKnitting = false;
  int invoiceWrites = 0, nativeWrites = 0;
  int knittingWrites = 0;
  Map<String, dynamic>? lastKnitting;
  int acknowledgementsStarted = 0, acknowledgementsPending = 0;
  final acknowledgementErrors = <Object>[];

  @override
  Future<void> acknowledgeOperation(String company, String requestId) async {
    acknowledgementsStarted++;
    acknowledgementsPending++;
    try {
      await super.acknowledgeOperation(company, requestId);
    } catch (error) {
      acknowledgementErrors.add(error);
      rethrow;
    } finally {
      acknowledgementsPending--;
    }
  }

  @override
  Future<Map<String, dynamic>> knittingCommand(
    String company,
    String action,
    Map<String, dynamic> values,
    String id, {
    String? modified,
  }) async {
    knittingWrites++;
    final result = await super.knittingCommand(
      company,
      action,
      values,
      id,
      modified: modified,
    );
    lastKnitting = result;
    if (dropKnitting) {
      dropKnitting = false;
      throw const ErpException('Synthetic response interruption after commit.');
    }
    return result;
  }

  @override
  Future<String> saveInvoiceDraft(
    Map<String, Object?> draft,
    String id,
    String review,
  ) async {
    invoiceWrites++;
    final name = await super.saveInvoiceDraft(draft, id, review);
    if (dropInvoice) {
      dropInvoice = false;
      throw const ErpException('Synthetic response interruption after commit.');
    }
    return name;
  }

  @override
  Future<NativeDocument> saveNative(
    NativeSchema schema,
    Map<String, dynamic> document, {
    String action = 'Save',
    String? requestId,
    String? company,
  }) async {
    nativeWrites++;
    final saved = await super.saveNative(
      schema,
      document,
      action: action,
      requestId: requestId,
      company: company,
    );
    if (dropNative) {
      dropNative = false;
      throw const ErpException('Synthetic response interruption after commit.');
    }
    return saved;
  }
}

// Real sockets need event-loop turns; advancing fake time can expire an HTTP
// timeout before the server has had a chance to answer.
Future<void> _ioTurn(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 25)),
  );
  await tester.pump();
}

Future<void> _waitForAcknowledgements(
  WidgetTester tester,
  _LostResponseApi api,
  int expected,
) async {
  // Pump once first so receipt post-frame callbacks can start their requests.
  await tester.pump();
  for (var i = 0; i < 1000; i++) {
    if (api.acknowledgementErrors.isNotEmpty ||
        api.acknowledgementsStarted >= expected &&
            api.acknowledgementsPending == 0) {
      break;
    }
    await _ioTurn(tester);
  }
  expect(api.acknowledgementErrors, isEmpty);
  expect(api.acknowledgementsStarted, greaterThanOrEqualTo(expected));
  expect(
    api.acknowledgementsPending,
    0,
    reason: 'Receipt acknowledgement did not finish within 25 seconds.',
  );
}

Future<void> _disposeConnected(
  WidgetTester tester,
  _ConnectedBinding binding,
  Iterable<_LostResponseApi> clients,
) async {
  // This must run inside the test body: addTearDown runs after the binding's
  // pending-timer invariant. Dispose listeners before closing their sockets.
  try {
    try {
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      for (final api in clients) {
        api.close();
      }
    }
    // Socket destruction delivers asynchronous errors to unfinished reads and
    // cancels their timeout timers. Also drain an aborted acknowledgement on a
    // failing scenario; a successful scenario already awaited its receipt.
    for (var i = 0; i < 100; i++) {
      await _ioTurn(tester);
      if (i >= 3 && clients.every((api) => api.acknowledgementsPending == 0)) {
        break;
      }
    }
  } finally {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await binding.setSurfaceSize(null);
    await tester.pump();
  }
  expect(clients.every((api) => api.acknowledgementsPending == 0), isTrue);
}

void main() {
  final binding = _ConnectedBinding();
  testWidgets(
    'synthetic mill entry reconciles a committed command without replay',
    (t) async {
      final path = Platform.environment['UX_FIXTURE_DIR'];
      if (path == null) {
        throw StateError(
          'Set UX_FIXTURE_DIR to the dedicated synthetic UX fixture.',
        );
      }
      final resultFile = File('$path/mill-ui-result.json');
      if (resultFile.existsSync()) {
        resultFile.deleteSync();
      }
      final mill =
          jsonDecode(File('$path/mill.json').readAsStringSync()) as Map;
      expect(mill['site'], 'native-test.localhost');
      expect(mill['origin'], 'http://127.0.0.1:8081');
      expect((mill['username'] as String).endsWith('@example.invalid'), true);
      expect(mill['company'], 'ERP Native Verification');
      final api = _LostResponseApi(Uri.parse('http://127.0.0.1:8081'))
        ..dropKnitting = true;
      addTearDown(api.close);
      late Map<String, Object?> result;
      try {
        final company = mill['company'] as String;
        await t.runAsync(
          () =>
              api.login(mill['username'] as String, mill['password'] as String),
        );
        final workspace = await t.runAsync(
          () => api.workspaceContext(company: company),
        );
        expect(workspace?.company, company);
        expect(workspace?.companies.length, 1);
        expect(api.supportsOperationRecovery(company), true);
        final catalog = await t.runAsync(
          () => api.nativeCatalog(company: company),
        );
        expect(catalog?.site, 'native-test.localhost');
        t.view.physicalSize = const Size(1440, 1100);
        t.view.devicePixelRatio = 1;
        await binding.setSurfaceSize(const Size(1440, 1100));
        Future<void> wait(Finder f) async {
          for (var i = 0; i < 250 && f.evaluate().isEmpty; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(
            f,
            findsWidgets,
            reason: t
                .widgetList<Text>(find.byType(Text))
                .map((w) => w.data ?? '')
                .join(' | '),
          );
          await t.pump(const Duration(milliseconds: 300));
        }

        await t.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme,
            home: KnittingCommandForm(
              api: api,
              workspace: workspace!,
              action: knitActions.firstWhere((a) => a.id == 'create_job'),
              initial: {
                'customer': mill['customer'],
                'kind': 'Order',
                'material_mode': 'Customer',
                'target_kg': '12.000',
                'rate': '100.00',
                'programme': [
                  {
                    'id': 'P1',
                    'fabric': 'UX native rehearsal jersey',
                    'colour': 'Natural',
                    'dia': '30',
                    'gauge': '24',
                    'knit_type': 'Tubular',
                    'gsm': [180],
                    'll': ['2.70'],
                    'target_kg': '12.000',
                    'fabric_item': mill['fabric_item'],
                  },
                ],
                'notes': 'Synthetic UX connected lost-response test',
              },
            ),
          ),
        );
        await t.tap(find.text('Review entry'));
        await t.pump(const Duration(milliseconds: 350));
        await wait(find.text('Confirm & post'));
        await t.tap(find.text('Confirm & post'));
        await t.pump();
        await wait(find.text('Check save status'));
        expect(api.knittingWrites, 1);
        await t.tap(find.text('Check save status'));
        await t.pump();
        await wait(find.text('Done'));
        expect(api.knittingWrites, 1);
        final job = (api.lastKnitting!['data'] as Map)['job'];
        final snapshot = await t.runAsync(
          () => api.knittingSnapshot(company, job: job as String),
        );
        expect(snapshot?.rows('jobs').single['name'], job);
        await _waitForAcknowledgements(t, api, 1);
        result = {
          'site': 'native-test.localhost',
          'company': company,
          'job': job,
          'writes': api.knittingWrites,
          'passed': true,
        };
      } finally {
        await _disposeConnected(t, binding, [api]);
      }
      expect(t.takeException(), isNull);
      resultFile.writeAsStringSync(jsonEncode(result));
      stdout.writeln(
        'UX connected knitting command recovered one real job: ${result['job']}',
      );
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
  testWidgets(
    'synthetic native-test UI preserves and recovers real committed work',
    (t) async {
      final path = Platform.environment['UX_FIXTURE_DIR'];
      if (path == null) {
        throw StateError(
          'Set UX_FIXTURE_DIR to the dedicated synthetic UX fixture.',
        );
      }
      final resultFile = File('$path/ui-result.json');
      if (resultFile.existsSync()) {
        resultFile.deleteSync();
      }
      final auth =
          jsonDecode(File('$path/owner.json').readAsStringSync()) as Map;
      final records =
          jsonDecode(File('$path/records.json').readAsStringSync()) as Map;
      expect(records['site'], 'native-test.localhost');
      expect(records['origin'], 'http://127.0.0.1:8081');
      expect((auth['username'] as String).endsWith('@example.invalid'), true);
      final company = records['company'] as String;
      expect(auth['username'], records['owner']);
      expect(auth['company'], company);
      expect(company, startsWith('Pilot Trade '));
      late _LostResponseApi api;
      final clients = <_LostResponseApi>[];
      late Map<String, Object?> result;
      try {
        t.view.physicalSize = const Size(1440, 1100);
        t.view.devicePixelRatio = 1;
        await binding.setSurfaceSize(const Size(1440, 1100));
        String visible() => t
            .widgetList<Text>(find.byType(Text))
            .map((w) => w.data ?? '')
            .where((s) => s.isNotEmpty)
            .join(' | ');
        Future<void> wait(Finder finder) async {
          for (var i = 0; i < 250 && finder.evaluate().isEmpty; i++) {
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(finder, findsWidgets, reason: visible());
          await t.pump(const Duration(milliseconds: 300));
        }

        Future<void> tap(Finder finder) async {
          await wait(finder);
          await t.ensureVisible(finder.first);
          await t.pump();
          expect(finder.first.hitTestable(), findsOneWidget);
          await t.tap(finder.first);
          await t.pump(const Duration(milliseconds: 350));
        }

        Future<void> input(String label, String value) async {
          final finder = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == label,
          );
          await wait(finder);
          await t.ensureVisible(finder.first);
          await t.enterText(finder.first, value);
          await t.pump();
        }

        Future<T?> open<T>(Widget screen) {
          final navigator = Navigator.of(
            t.element(find.byType(WorkspaceShell)),
          );
          return navigator.push<T>(MaterialPageRoute(builder: (_) => screen));
        }

        await t.pumpWidget(
          MaterialApp(
            theme: WorkspaceTheme.theme,
            home: WorkspaceShell(
              connect: (uri) {
                if (![
                  'http://localhost:8081',
                  'http://127.0.0.1:8081',
                ].contains(uri.toString())) {
                  throw StateError('Refusing non-test service.');
                }
                final connected = _LostResponseApi(uri);
                clients.add(connected);
                addTearDown(connected.close);
                return api = connected;
              },
            ),
          ),
        );
        await input('Username', auth['username'] as String);
        await input('Password', auth['password'] as String);
        await tap(find.text('Enter workspace'));
        await wait(find.byTooltip('Workspace options'));
        final catalog = await t.runAsync(
          () => api.nativeCatalog(company: company),
        );
        expect(catalog?.site, 'native-test.localhost');
        final workspace = await t.runAsync(
          () => api.workspaceContext(company: company),
        );
        expect(workspace?.company, company);
        expect(workspace?.companies.length, 1);
        expect(api.supportsOperationRecovery(company), true);
        stdout.writeln(
          'UX authenticated synthetic owner on verified native-test.localhost',
        );

        await tap(find.byTooltip('Workspace options'));
        await tap(find.text('Pending operations'));
        await wait(find.byType(PendingOperationsScreen));
        final preparedId = (records['requests'] as Map)['prepared'] as String;
        final card = find.ancestor(
          of: find.text('Reference · $preparedId'),
          matching: find.byType(Card),
        );
        await wait(card);
        final previousStatus = await t.runAsync(
          () => api.operationStatus(company, preparedId),
        );
        if (previousStatus?['state'] == 'prepared') {
          await tap(
            find.descendant(
              of: card,
              matching: find.text('Close unposted request'),
            ),
          );
        }
        await wait(
          find.descendant(
            of: card,
            matching: find.text('Closed without posting'),
          ),
        );
        final closed = await t.runAsync(
          () => api.operationStatus(company, preparedId),
        );
        expect(closed?['state'], 'closed');
        await t.pageBack();
        await t.pump(const Duration(milliseconds: 350));
        stdout.writeln(
          'UX pending operation discovered after sign-in and safely closed',
        );

        api.dropInvoice = true;
        final created = open<String>(
          InvoiceComposer(api: api, company: company),
        );
        await wait(find.text('New sales invoice'));
        await wait(
          find.textContaining(RegExp(r'^Invoice date · \d{4}-\d{2}-\d{2}$')),
        );
        await input('Customer', records['customer'] as String);
        await input('Item or service', records['item'] as String);
        await input('Quantity', '2');
        await input('Rate override', '10');
        await tap(find.text('Review invoice'));
        await wait(find.text('Save draft'));
        await tap(find.text('Save draft'));
        await wait(find.text('Check save status'));
        expect(api.invoiceWrites, 1);
        await tap(find.text('Check save status'));
        await wait(find.byTooltip('Workspace options'));
        final name = await created;
        expect(name, isNotNull);
        expect(api.invoiceWrites, 1);
        final saved = await t.runAsync(
          () =>
              api.nativeDocument('Sales Invoice', name: name, company: company),
        );
        expect(saved?.data['docstatus'], 0);
        expect(saved?.data['customer'], records['customer']);
        await _waitForAcknowledgements(t, api, 1);
        stdout.writeln(
          'UX lost invoice response recovered one committed draft: $name',
        );

        api.dropNative = true;
        final customerName = records['recovered_customer'] as String;
        final editor = open<void>(
          DocumentEditor(
            api: api,
            company: company,
            doctype: 'Customer',
            name: customerName,
          ),
        );
        final customerField = find.byWidgetPredicate(
          (w) => w is NativeScalarField && w.field.name == 'customer_name',
        );
        await wait(customerField);
        final field = find.descendant(
          of: customerField,
          matching: find.byType(TextFormField),
        );
        await t.ensureVisible(field);
        await t.enterText(
          field,
          'UX verified customer ${DateTime.now().millisecondsSinceEpoch}',
        );
        await tap(find.text('Save'));
        await wait(find.text('Check outcome'));
        expect(api.nativeWrites, 1);
        await tap(find.text('Check outcome'));
        await wait(find.text('Save confirmed'));
        expect(api.nativeWrites, 1);
        await t.pageBack();
        await t.pump(const Duration(milliseconds: 350));
        await editor;
        await _waitForAcknowledgements(t, api, 2);
        result = {
          'site': 'native-test.localhost',
          'company': company,
          'invoice': name,
          'invoice_writes': api.invoiceWrites,
          'native_writes': api.nativeWrites,
          'pending_closed': preparedId,
          'passed': true,
        };
      } finally {
        await _disposeConnected(t, binding, clients);
      }
      expect(t.takeException(), isNull);
      resultFile.writeAsStringSync(jsonEncode(result));
      stdout.writeln(
        'UX connected recovery and work-retention rehearsal passed',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
